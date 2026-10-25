import Foundation
import AppKit

/// Dot-localization protocol (participant-facing).
/// Timeline: fixation → optional HRTF chirp → delay → L/R dot (or catch) → F/J response.
/// Timing uses ProcessInfo.systemUptime.
final class TrialEngine {
    struct Timing {
        /// Static cross before anything else.
        var fixationMs: ClosedRange<Int> = 400...700
        /// Delay after (optional) sound until the dot — also the mock EEG window.
        var delayMs: ClosedRange<Int> = 500...1500
        /// Dot flash duration.
        var targetMs: ClosedRange<Int> = 150...250
        var responseMs: Int = 1500
        var feedbackMs: Int = 250
        var itiMs: Int = 400
    }

    var timing = Timing()
    var onPhaseChange: ((TrialPhase) -> Void)?
    var onTrialComplete: ((TrialRecord) -> Void)?

    private(set) var phase: TrialPhase = .idle
    private(set) var trialId = 0
    private var running = false
    private var currentSpec: TrialSpec?
    /// Logged as cue_onset — moment of HRTF chirp (or delay start if no-sound).
    private var cueOnset: TimeInterval = 0
    private var anticipatoryStart: TimeInterval = 0
    private var anticipatoryEnd: TimeInterval = 0
    private var targetOnset: TimeInterval = 0

    private let eeg: EEGSource
    private let decoder: ModulationDecoder
    private let logger: TrialLogger
    private let audio: SpatialAudioEngine
    private let participantId: String

    init(
        eeg: EEGSource,
        decoder: ModulationDecoder,
        logger: TrialLogger,
        audio: SpatialAudioEngine,
        participantId: String
    ) {
        self.eeg = eeg
        self.decoder = decoder
        self.logger = logger
        self.audio = audio
        self.participantId = participantId
    }

    func stop() {
        running = false
        audio.stop()
        setPhase(.idle)
    }

    /// Run `count` trials for a block; returns when finished.
    func runBlock(
        count: Int,
        mode: ExperimentMode,
        soundAngleDeg: Double,
        catchRate: Double = 0.18
    ) async -> [TrialRecord] {
        running = true
        var out: [TrialRecord] = []
        for _ in 0..<count {
            guard running else { break }
            let spec = makeSpec(mode: mode, soundAngleDeg: soundAngleDeg, catchRate: catchRate)
            if let record = await runOne(spec: spec) {
                out.append(record)
                onTrialComplete?(record)
            }
        }
        audio.stop()
        setPhase(.idle)
        return out
    }

    private func makeSpec(mode: ExperimentMode, soundAngleDeg: Double, catchRate: Double) -> TrialSpec {
        let isCatch = Double.random(in: 0...1) < catchRate
        if isCatch {
            // Internal side for mock EEG balance only — never shown as an arrow.
            let internalSide: Side = Bool.random() ? .left : .right
            return TrialSpec(
                cueSide: internalSide,
                targetSide: nil,
                targetPresent: false,
                mode: mode,
                soundAngleDeg: soundAngleDeg
            )
        }
        let side: Side = Bool.random() ? .left : .right
        // cueSide == targetSide: mock attend-L/R swing follows **dot side**, not a visual arrow.
        return TrialSpec(
            cueSide: side,
            targetSide: side,
            targetPresent: true,
            mode: mode,
            soundAngleDeg: soundAngleDeg
        )
    }

    private func runOne(spec: TrialSpec) async -> TrialRecord? {
        currentSpec = spec
        trialId += 1
        // Condition side for mock EEG = cueSide (= dot side when present).
        eeg.setContext(cueSide: spec.cueSide, soundAngleDeg: spec.soundAngleDeg)

        // 1. Static fixation
        setPhase(.fixation)
        await sleepMs(Int.random(in: timing.fixationMs))
        guard running else { return nil }

        // 2. Optional short HRTF chirp (no visual arrow)
        cueOnset = now()
        if !SoundAngle.isNone(spec.soundAngleDeg) {
            audio.playChirp(azimuthDegrees: spec.soundAngleDeg)
        } else {
            audio.stop()
        }
        // Stay on fixation while sound plays / brief settle
        setPhase(.fixation)
        await sleepMs(120)
        guard running else { return nil }

        // 3. Delay (EEG window) — still only the cross
        anticipatoryStart = now()
        setPhase(.waitForDot)
        await sleepMs(Int.random(in: timing.delayMs))
        anticipatoryEnd = now()
        guard running else { return nil }

        let eegWindow = eeg.window(from: anticipatoryStart, to: anticipatoryEnd)
        let sample = decoder.decode(window: eegWindow)

        // 4. Dot flash (or catch: nothing)
        let flashMs = Int.random(in: timing.targetMs)
        targetOnset = now()
        setPhase(.target(spec.targetSide))
        await sleepMs(flashMs)
        guard running else { return nil }

        // 5. Response
        setPhase(.response(spec.targetSide))
        let deadline = now() + Double(timing.responseMs) / 1000.0
        let response = await waitForKey(until: deadline)
        guard running else { return nil }

        let (correct, rt, respOnset) = score(spec: spec, response: response)

        let record = TrialRecord(
            participantId: participantId,
            trialId: trialId,
            mode: spec.mode.rawValue,
            soundAngleDeg: spec.soundAngleDeg,
            cueSide: spec.cueSide.rawValue,
            targetSide: spec.targetSide?.rawValue ?? "none",
            targetPresent: spec.targetPresent,
            cueOnset: cueOnset,
            anticipatoryStart: anticipatoryStart,
            anticipatoryEnd: anticipatoryEnd,
            targetOnset: targetOnset,
            responseOnset: respOnset,
            correct: correct,
            reactionTimeMs: rt,
            artifactFlag: !sample.qualityOK,
            alphaPo7: sample.alphaPO7,
            alphaPo8: sample.alphaPO8,
            lateralization: sample.lateralization,
            eegSource: eeg.sourceKind.rawValue
        )
        logger.append(record)

        // 6. Brief feedback
        setPhase(.feedback(correct == true ? "✓" : (correct == false ? "✗" : "·")))
        await sleepMs(timing.feedbackMs)
        setPhase(.interTrial)
        await sleepMs(timing.itiMs)
        return record
    }

    private func score(spec: TrialSpec, response: (key: Side?, time: TimeInterval)?) -> (Bool?, Double?, Double?) {
        guard let response else {
            return (spec.targetPresent ? false : true, nil, nil)
        }
        let rt = (response.time - targetOnset) * 1000
        if !spec.targetPresent {
            return (false, rt, response.time)
        }
        return (response.key == spec.targetSide, rt, response.time)
    }

    private func waitForKey(until deadline: TimeInterval) async -> (key: Side?, time: TimeInterval)? {
        while now() < deadline {
            if let hit = KeyMonitor.shared.consume() {
                return hit
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return nil
    }

    private func setPhase(_ p: TrialPhase) {
        phase = p
        DispatchQueue.main.async { self.onPhaseChange?(p) }
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func sleepMs(_ ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }
}

/// Global key monitor installed by the experiment window.
final class KeyMonitor {
    static let shared = KeyMonitor()
    private var pending: (key: Side?, time: TimeInterval)?
    private var monitor: Any?

    func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let t = ProcessInfo.processInfo.systemUptime
            // F / J (primary) or ← / →
            switch event.keyCode {
            case 123, 3: // left arrow / f
                self?.pending = (.left, t)
            case 124, 38: // right arrow / j
                self?.pending = (.right, t)
            default:
                break
            }
            return event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func consume() -> (key: Side?, time: TimeInterval)? {
        defer { pending = nil }
        return pending
    }
}

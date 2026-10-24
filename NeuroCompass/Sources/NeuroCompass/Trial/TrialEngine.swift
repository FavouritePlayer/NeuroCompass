import Foundation
import AppKit

/// Runs the cued attention protocol (design A4). Timing uses ProcessInfo.systemUptime.
final class TrialEngine {
    struct Timing {
        var fixationMs: ClosedRange<Int> = 500...800
        var cueMs: Int = 200
        var anticipatoryMs: ClosedRange<Int> = 1000...1500
        var targetMs: Int = 120
        var responseMs: Int = 1500
        var itiMs: Int = 400
    }

    var timing = Timing()
    var onPhaseChange: ((TrialPhase) -> Void)?
    var onTrialComplete: ((TrialRecord) -> Void)?

    private(set) var phase: TrialPhase = .idle
    private(set) var trialId = 0
    private var running = false
    private var currentSpec: TrialSpec?
    private var cueOnset: TimeInterval = 0
    private var anticipatoryStart: TimeInterval = 0
    private var anticipatoryEnd: TimeInterval = 0
    private var targetOnset: TimeInterval = 0
    private var responseDeadline: TimeInterval = 0
    private var responded = false
    private var workItem: DispatchWorkItem?

    private let eeg: EEGSource
    private let decoder: ModulationDecoder
    private let logger: TrialLogger
    private let participantId: String

    init(eeg: EEGSource, decoder: ModulationDecoder, logger: TrialLogger, participantId: String) {
        self.eeg = eeg
        self.decoder = decoder
        self.logger = logger
        self.participantId = participantId
    }

    func stop() {
        running = false
        workItem?.cancel()
        setPhase(.idle)
    }

    /// Run `count` trials for a block; returns when finished.
    func runBlock(
        count: Int,
        mode: ExperimentMode,
        multiplier: Double,
        catchRate: Double = 0.18
    ) async -> [TrialRecord] {
        running = true
        var out: [TrialRecord] = []
        for _ in 0..<count {
            guard running else { break }
            let spec = makeSpec(mode: mode, multiplier: multiplier, catchRate: catchRate)
            if let record = await runOne(spec: spec) {
                out.append(record)
                onTrialComplete?(record)
            }
        }
        setPhase(.idle)
        return out
    }

    private func makeSpec(mode: ExperimentMode, multiplier: Double, catchRate: Double) -> TrialSpec {
        let cue: Side = Bool.random() ? .left : .right
        let isCatch = Double.random(in: 0...1) < catchRate
        if isCatch {
            return TrialSpec(cueSide: cue, targetSide: nil, targetPresent: false, mode: mode, shaderMultiplier: multiplier)
        }
        // Balanced targets independent of cue (Posner-style validity can be added later).
        let target: Side = Bool.random() ? .left : .right
        return TrialSpec(cueSide: cue, targetSide: target, targetPresent: true, mode: mode, shaderMultiplier: multiplier)
    }

    private func runOne(spec: TrialSpec) async -> TrialRecord? {
        currentSpec = spec
        responded = false
        trialId += 1
        eeg.setContext(cueSide: nil, multiplier: spec.shaderMultiplier)

        // Fixation
        setPhase(.fixation)
        await sleepMs(Int.random(in: timing.fixationMs))
        guard running else { return nil }

        // Cue
        cueOnset = now()
        setPhase(.cue(spec.cueSide))
        eeg.setContext(cueSide: spec.cueSide, multiplier: spec.shaderMultiplier)
        await sleepMs(timing.cueMs)
        guard running else { return nil }

        // Anticipatory (EEG window)
        anticipatoryStart = now()
        setPhase(.anticipatory(spec.cueSide))
        await sleepMs(Int.random(in: timing.anticipatoryMs))
        anticipatoryEnd = now()
        guard running else { return nil }

        let eegWindow = eeg.window(from: anticipatoryStart, to: anticipatoryEnd)
        let sample = decoder.decode(window: eegWindow)

        // Target
        targetOnset = now()
        setPhase(.target(spec.targetSide))
        await sleepMs(timing.targetMs)
        guard running else { return nil }

        // Response
        setPhase(.response(spec.targetSide))
        responseDeadline = now() + Double(timing.responseMs) / 1000.0
        let response = await waitForKey(until: responseDeadline)
        guard running else { return nil }

        let (correct, rt, respOnset) = score(spec: spec, response: response)

        let record = TrialRecord(
            participantId: participantId,
            trialId: trialId,
            mode: spec.mode.rawValue,
            shaderMultiplier: spec.shaderMultiplier,
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
        setPhase(.feedback(correct == true ? "✓" : (correct == false ? "✗" : "·")))
        await sleepMs(250)
        setPhase(.interTrial)
        await sleepMs(timing.itiMs)
        return record
    }

    private func score(spec: TrialSpec, response: (key: Side?, time: TimeInterval)?) -> (Bool?, Double?, Double?) {
        guard let response else {
            // No response: incorrect if target present; correct (true reject) if catch.
            return (spec.targetPresent ? false : true, nil, nil)
        }
        let rt = (response.time - targetOnset) * 1000
        if !spec.targetPresent {
            // False alarm if any key on catch
            return (false, rt, response.time)
        }
        let ok = response.key == spec.targetSide
        return (ok, rt, response.time)
    }

    // Key monitoring via shared KeyMonitor
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
            // f / j or left / right arrows
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

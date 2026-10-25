import Foundation

/// Grid calibration over HRTF sound angles (replaces left-contrast multipliers).
///
/// Core API: `trySetting(soundAngleDeg) → ModulationResult`
/// `0` = no-sound baseline; otherwise azimuth in degrees (e.g. −30 / −45 / −60).
/// Each step plays an HRTF cue and updates the operator angle display.
final class CalibrationLoop {
    static let defaultGrid: [Double] = SoundAngle.grid

    private let trialEngine: TrialEngine
    private let audio: SpatialAudioEngine
    private let trialsPerSetting: Int

    /// Update UI when the active sound angle changes.
    var onApplySoundAngle: ((Double) -> Void)?
    var onProgress: ((String) -> Void)?
    var onModulation: ((ModulationResult) -> Void)?

    init(trialEngine: TrialEngine, audio: SpatialAudioEngine, trialsPerSetting: Int = 8) {
        self.trialEngine = trialEngine
        self.audio = audio
        self.trialsPerSetting = trialsPerSetting
    }

    /// Apply HRTF angle (or silence), run a cued block, return measured modulation.
    func trySetting(_ soundAngleDeg: Double, mode: ExperimentMode = .adjusted) async -> ModulationResult {
        let label = SoundAngle.label(soundAngleDeg)
        onProgress?("Sound setting \(label)")
        await MainActor.run {
            onApplySoundAngle?(soundAngleDeg)
        }
        if SoundAngle.isNone(soundAngleDeg) {
            audio.stop()
        } else {
            audio.play(azimuthDegrees: soundAngleDeg)
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        onProgress?("Running \(trialsPerSetting) cued trials @ \(label)…")
        let trials = await trialEngine.runBlock(
            count: trialsPerSetting,
            mode: mode,
            soundAngleDeg: soundAngleDeg
        )
        audio.stop()
        let result = measureModulation(soundAngleDeg: soundAngleDeg, trials: trials)
        onModulation?(result)
        return result
    }

    /// Grid search. Locks the angle with strongest leftward modulation.
    /// On uncertain differences, defaults to no-sound (0) and reports why.
    func runGrid(angles: [Double] = CalibrationLoop.defaultGrid) async -> CalibrationOutcome {
        var results: [ModulationResult] = []
        let order = angles.shuffled()
        for a in order {
            let r = await trySetting(a, mode: .adjusted)
            results.append(r)
        }
        results.sort { $0.soundAngleDeg < $1.soundAngleDeg }

        let valid = results.filter { !$0.uncertain }
        guard let best = valid.max(by: { $0.modulation < $1.modulation }) else {
            await MainActor.run { onApplySoundAngle?(SoundAngle.none) }
            audio.stop()
            return CalibrationOutcome(
                results: results,
                lockedAngleDeg: SoundAngle.none,
                lockedUncertain: true,
                message: "Uncertain differences — defaulting to no-sound (neutral)."
            )
        }

        let sorted = valid.sorted { $0.modulation > $1.modulation }
        let eps = 0.02
        if sorted.count >= 2, abs(sorted[0].modulation - sorted[1].modulation) < eps {
            await MainActor.run { onApplySoundAngle?(SoundAngle.none) }
            audio.stop()
            return CalibrationOutcome(
                results: results,
                lockedAngleDeg: SoundAngle.none,
                lockedUncertain: true,
                message: String(
                    format: "Top settings nearly tied (Δ=%.3f < %.2f) — defaulting to no-sound.",
                    abs(sorted[0].modulation - sorted[1].modulation),
                    eps
                )
            )
        }

        await MainActor.run { onApplySoundAngle?(best.soundAngleDeg) }
        if !SoundAngle.isNone(best.soundAngleDeg) {
            audio.play(azimuthDegrees: best.soundAngleDeg)
        }
        return CalibrationOutcome(
            results: results,
            lockedAngleDeg: best.soundAngleDeg,
            lockedUncertain: false,
            message: String(
                format: "Locked sound %@ (modulation=%.3f). eeg_source=mock",
                SoundAngle.label(best.soundAngleDeg),
                best.modulation
            )
        )
    }

    /// HOOK — future step-based optimizer should only call `trySetting`.
    func runStepBasedOptimizerPlaceholder(start: Double = SoundAngle.demoOptimum, maxSteps: Int = 6) async -> CalibrationOutcome {
        _ = await trySetting(start)
        return await runGrid()
    }

    func measureModulation(soundAngleDeg: Double, trials: [TrialRecord]) -> ModulationResult {
        let leftCues = trials.filter { $0.cueSide == "left" && !$0.artifactFlag }
        let rightCues = trials.filter { $0.cueSide == "right" && !$0.artifactFlag }
        let meanL = average(leftCues.map(\.lateralization))
        let meanR = average(rightCues.map(\.lateralization))
        let modulation = meanL - meanR
        let uncertain = leftCues.isEmpty || rightCues.isEmpty

        let leftTargets = trials.filter { $0.targetSide == "left" && $0.targetPresent }
        let rightTargets = trials.filter { $0.targetSide == "right" && $0.targetPresent }
        let rts = trials.compactMap(\.reactionTimeMs).sorted()
        let medianRT = rts.isEmpty ? 0 : rts[rts.count / 2]
        let catches = trials.filter { !$0.targetPresent }
        let fa = catches.isEmpty ? 0 : Double(catches.filter { $0.correct == false }.count) / Double(catches.count)

        return ModulationResult(
            soundAngleDeg: soundAngleDeg,
            modulation: modulation,
            uncertain: uncertain,
            reason: uncertain ? "Too few clean cue-L/cue-R trials" : "ok",
            trialCount: trials.count,
            hitRateLeft: hitRate(leftTargets),
            hitRateRight: hitRate(rightTargets),
            medianRTMs: medianRT,
            falseAlarmRate: fa
        )
    }

    private func average(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private func hitRate(_ trials: [TrialRecord]) -> Double {
        guard !trials.isEmpty else { return 0 }
        return Double(trials.filter { $0.correct == true }.count) / Double(trials.count)
    }
}

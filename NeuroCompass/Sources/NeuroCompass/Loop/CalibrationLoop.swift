import Foundation

/// Grid calibration over left-contrast multipliers.
///
/// Core API: `trySetting(multiplier) → ModulationResult`
/// Grid search sits on that API. Future step-based optimizers should only call `trySetting`
/// (see `runStepBasedOptimizerPlaceholder`).
final class CalibrationLoop {
    static let defaultGrid: [Double] = [0.85, 1.00, 1.15, 1.30]

    private let trialEngine: TrialEngine
    private let shade: ScreenShadeDriver
    private let trialsPerSetting: Int
    var onProgress: ((String) -> Void)?
    var onModulation: ((ModulationResult) -> Void)?

    init(trialEngine: TrialEngine, shade: ScreenShadeDriver, trialsPerSetting: Int = 8) {
        self.trialEngine = trialEngine
        self.shade = shade
        self.trialsPerSetting = trialsPerSetting
    }

    /// Apply a contrast setting on ScreenShade, run a cued block, return measured modulation.
    func trySetting(_ multiplier: Double, mode: ExperimentMode = .adjusted) async -> ModulationResult {
        onProgress?("Applying left-contrast ×\(String(format: "%.2f", multiplier)) → ScreenShade loop.json")
        shade.apply(leftContrastMultiplier: multiplier, enabled: true)
        // Brief settle so ScreenShade poll (~0.25s) picks up the file.
        try? await Task.sleep(nanoseconds: 400_000_000)

        onProgress?("Running \(trialsPerSetting) cued trials @ ×\(String(format: "%.2f", multiplier))…")
        let trials = await trialEngine.runBlock(
            count: trialsPerSetting,
            mode: mode,
            multiplier: multiplier
        )
        let result = measureModulation(multiplier: multiplier, trials: trials)
        onModulation?(result)
        return result
    }

    /// Grid search. Locks the multiplier with strongest leftward modulation.
    /// On uncertain differences, defaults to neutral (1.0) and reports why.
    func runGrid(multipliers: [Double] = CalibrationLoop.defaultGrid) async -> CalibrationOutcome {
        var results: [ModulationResult] = []
        let order = multipliers.shuffled()
        for m in order {
            let r = await trySetting(m, mode: .adjusted)
            results.append(r)
        }
        results.sort { $0.multiplier < $1.multiplier }

        let valid = results.filter { !$0.uncertain }
        guard let best = valid.max(by: { $0.modulation < $1.modulation }) else {
            shade.apply(leftContrastMultiplier: 1.0)
            return CalibrationOutcome(
                results: results,
                lockedMultiplier: 1.0,
                lockedUncertain: true,
                message: "Uncertain differences across settings — defaulting to neutral (1.00)."
            )
        }

        // Uncertainty: if top two are within epsilon, treat as uncertain.
        let sorted = valid.sorted { $0.modulation > $1.modulation }
        let eps = 0.02
        if sorted.count >= 2, abs(sorted[0].modulation - sorted[1].modulation) < eps {
            shade.apply(leftContrastMultiplier: 1.0)
            return CalibrationOutcome(
                results: results,
                lockedMultiplier: 1.0,
                lockedUncertain: true,
                message: String(
                    format: "Top settings nearly tied (Δ=%.3f < %.2f) — defaulting to neutral (1.00).",
                    abs(sorted[0].modulation - sorted[1].modulation),
                    eps
                )
            )
        }

        shade.apply(leftContrastMultiplier: best.multiplier)
        return CalibrationOutcome(
            results: results,
            lockedMultiplier: best.multiplier,
            lockedUncertain: false,
            message: String(
                format: "Locked left-contrast ×%.2f (modulation=%.3f).",
                best.multiplier,
                best.modulation
            )
        )
    }

    /// HOOK — future step-based optimizer.
    /// Replace the body with hill-climbing / Bayesian steps that only call `trySetting`.
    /// Do not rewrite trial or EEG plumbing when swapping search strategies.
    func runStepBasedOptimizerPlaceholder(start: Double = 1.0, maxSteps: Int = 6) async -> CalibrationOutcome {
        // Placeholder: one evaluation at start, then defer to grid.
        _ = await trySetting(start)
        return await runGrid()
    }

    /// modulation = mean(lat | cue=left) − mean(lat | cue=right)
    func measureModulation(multiplier: Double, trials: [TrialRecord]) -> ModulationResult {
        let leftCues = trials.filter { $0.cueSide == "left" && !$0.artifactFlag }
        let rightCues = trials.filter { $0.cueSide == "right" && !$0.artifactFlag }
        let meanL = average(leftCues.map(\.lateralization))
        let meanR = average(rightCues.map(\.lateralization))
        let modulation = meanL - meanR

        let minN = 2
        let uncertain = leftCues.count < minN || rightCues.count < minN

        let leftTargets = trials.filter { $0.targetSide == "left" && $0.targetPresent }
        let rightTargets = trials.filter { $0.targetSide == "right" && $0.targetPresent }
        let hitL = hitRate(leftTargets)
        let hitR = hitRate(rightTargets)
        let rts = trials.compactMap(\.reactionTimeMs).sorted()
        let medianRT = rts.isEmpty ? 0 : rts[rts.count / 2]
        let catches = trials.filter { !$0.targetPresent }
        let fa = catches.isEmpty ? 0 : Double(catches.filter { $0.correct == false }.count) / Double(catches.count)

        return ModulationResult(
            multiplier: multiplier,
            modulation: modulation,
            uncertain: uncertain,
            reason: uncertain ? "Too few clean cue-L/cue-R trials" : "ok",
            trialCount: trials.count,
            hitRateLeft: hitL,
            hitRateRight: hitR,
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
        let hits = trials.filter { $0.correct == true }.count
        return Double(hits) / Double(trials.count)
    }
}

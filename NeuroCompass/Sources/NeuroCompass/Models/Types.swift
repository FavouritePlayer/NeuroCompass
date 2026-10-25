import Foundation

enum Side: String, Codable, CaseIterable {
    case left, right
}

enum ExperimentMode: String, Codable, CaseIterable {
    case neutral
    case leftDegraded = "left_degraded" // degraded-equivalent: no-sound / silent baseline block
    case adjusted
    case heldOut = "held_out"

    var displayName: String {
        switch self {
        case .neutral: return "neutral (no sound)"
        case .leftDegraded: return "no-sound"
        case .adjusted: return "adjusted"
        case .heldOut: return "held-out"
        }
    }
}

enum EEGSourceKind: String, Codable {
    case mock
    case live
}

/// Sound setting: `nil` / use `SoundAngle.none` sentinel `0` = no-sound baseline.
enum SoundAngle {
    /// No HRTF cue (neutral / baseline). Stored as 0 in CSV.
    static let none: Double = 0
    static let grid: [Double] = [none, -30, -45, -60]
    static let demoOptimum: Double = -45

    static func label(_ deg: Double) -> String {
        if abs(deg) < 0.001 { return "no-sound" }
        return String(format: "%+.0f°", deg)
    }

    static func isNone(_ deg: Double) -> Bool { abs(deg) < 0.001 }
}

struct LateralizationSample: Equatable {
    var alphaPO7: Double
    var alphaPO8: Double
    /// (P_PO8 − P_PO7) / (P_PO8 + P_PO7 + eps)
    var lateralization: Double
    var qualityOK: Bool
}

struct ModulationResult: Equatable {
    /// HRTF azimuth degrees; `0` = no-sound baseline.
    var soundAngleDeg: Double
    var modulation: Double
    var uncertain: Bool
    var reason: String
    var trialCount: Int
    var hitRateLeft: Double
    var hitRateRight: Double
    var medianRTMs: Double
    var falseAlarmRate: Double

    /// Back-compat alias used in a few call sites during migration.
    var multiplier: Double { soundAngleDeg }
}

struct CalibrationOutcome: Equatable {
    var results: [ModulationResult]
    var lockedAngleDeg: Double
    var lockedUncertain: Bool
    var message: String

    var lockedMultiplier: Double { lockedAngleDeg }
}

struct TrialSpec: Equatable {
    /// Internal condition side for mock EEG L/R swing — **not** a visible arrow.
    /// When a dot is present, equals `targetSide` (dot side). On catch trials, random for balance.
    var cueSide: Side
    var targetSide: Side?
    var targetPresent: Bool
    var mode: ExperimentMode
    var soundAngleDeg: Double
}

struct TrialRecord: Codable, Equatable {
    var participantId: String
    var trialId: Int
    var mode: String
    var soundAngleDeg: Double
    var cueSide: String
    var targetSide: String
    var targetPresent: Bool
    var cueOnset: Double
    var anticipatoryStart: Double
    var anticipatoryEnd: Double
    var targetOnset: Double
    var responseOnset: Double?
    var correct: Bool?
    var reactionTimeMs: Double?
    var artifactFlag: Bool
    var alphaPo7: Double
    var alphaPo8: Double
    var lateralization: Double
    var eegSource: String

    /// Legacy name kept for any external readers expecting shader_multiplier column mapping.
    var shaderMultiplier: Double { soundAngleDeg }
}

enum TrialPhase: Equatable {
    case idle
    /// Fixation cross only (may coincide with HRTF chirp — no arrow).
    case fixation
    /// Delay before dot; cross only. EEG window for mock decoder.
    case waitForDot
    /// Dot on left/right, or nil for catch (no press).
    case target(Side?)
    case response(Side?)
    case feedback(String)
    case interTrial
}

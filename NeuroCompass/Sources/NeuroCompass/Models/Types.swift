import Foundation

enum Side: String, Codable, CaseIterable {
    case left, right
}

enum ExperimentMode: String, Codable, CaseIterable {
    case neutral
    case leftDegraded = "left_degraded"
    case adjusted
    case heldOut = "held_out"

    var displayName: String {
        switch self {
        case .neutral: return "neutral"
        case .leftDegraded: return "left-degraded"
        case .adjusted: return "adjusted"
        case .heldOut: return "held-out"
        }
    }
}

enum EEGSourceKind: String, Codable {
    case mock
    case live
}

struct LateralizationSample: Equatable {
    var alphaPO7: Double
    var alphaPO8: Double
    /// (P_PO8 − P_PO7) / (P_PO8 + P_PO7 + eps)
    var lateralization: Double
    var qualityOK: Bool
}

struct ModulationResult: Equatable {
    var multiplier: Double
    /// Primary objective: mean alpha(attend-L) − alpha(attend-R) proxy = mean lat_L − mean lat_R...
    /// Convention: modulation = mean(lat | cue=left) − mean(lat | cue=right), steered toward
    /// a stronger **leftward** swing (larger positive values preferred for this MVP mock).
    var modulation: Double
    var uncertain: Bool
    var reason: String
    var trialCount: Int
    var hitRateLeft: Double
    var hitRateRight: Double
    var medianRTMs: Double
    var falseAlarmRate: Double
}

struct CalibrationOutcome: Equatable {
    var results: [ModulationResult]
    var lockedMultiplier: Double
    var lockedUncertain: Bool
    var message: String
}

struct TrialSpec: Equatable {
    var cueSide: Side
    var targetSide: Side?
    var targetPresent: Bool
    var mode: ExperimentMode
    var shaderMultiplier: Double
}

struct TrialRecord: Codable, Equatable {
    var participantId: String
    var trialId: Int
    var mode: String
    var shaderMultiplier: Double
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
}

enum TrialPhase: Equatable {
    case idle
    case fixation
    case cue(Side)
    case anticipatory(Side)
    case target(Side?)
    case response(Side?)
    case feedback(String)
    case interTrial
}

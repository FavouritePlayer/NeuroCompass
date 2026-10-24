import Foundation

/// Continuous EEG sample buffer (8 channels @ 250 Hz layout matching design A7).
/// Channel order: Fz, C3, Cz, C4, Pz, PO7, Oz, PO8
struct EEGWindow {
    var sampleRate: Double
    var startTime: TimeInterval
    var endTime: TimeInterval
    /// samples[channel][t]
    var samples: [[Double]]
    var source: EEGSourceKind
}

protocol EEGSource: AnyObject {
    var sourceKind: EEGSourceKind { get }
    var isConnected: Bool { get }
    var qualityOK: Bool { get }
    /// Latest raw sample count (for physiology panel).
    var sampleCount: Int { get }
    func start()
    func stop()
    /// Extract samples overlapping [start, end] in the same monotonic clock as the task.
    func window(from start: TimeInterval, to end: TimeInterval) -> EEGWindow
    /// Optional: inform mock stream of current cue / multiplier so it can synthesize a response.
    func setContext(cueSide: Side?, multiplier: Double)
}

extension EEGSource {
    func setContext(cueSide: Side?, multiplier: Double) {}
}

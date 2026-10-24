import Foundation

/// Labeled **mock** EEG stream (Mac default). Never reports `live`.
///
/// ## Deterministic demo bias (documented rule)
/// Response gain peaks at left-contrast multiplier **1.15**:
/// `gain = exp(-((m - 1.15) / 0.22)^2)`
///
/// When cue = left, PO8 amplitude > PO7 → positive lateralization.
/// When cue = right, PO7 amplitude > PO8 → negative lateralization.
/// Modulation ≈ mean(lat|cueL) − mean(lat|cueR) is therefore **largest near ×1.15**,
/// so the grid should lock ~1.15 (or neutral if too few trials / uncertain).
///
/// No random noise — same cue+multiplier → same lateralization direction/strength.
final class MockEEGSource: EEGSource {
    let sourceKind: EEGSourceKind = .mock
    private(set) var isConnected = false
    private(set) var qualityOK = true
    private(set) var sampleCount = 0

    /// Documented peak used by the demo bias.
    static let demoOptimumMultiplier: Double = 1.15

    private let sampleRate: Double = 250
    private var buffer: [[Double]] = Array(repeating: [], count: 8)
    private var times: [TimeInterval] = []
    private var timer: Timer?
    private var cueSide: Side?
    private var multiplier: Double = 1.0
    private var t0: TimeInterval = 0
    private var tickIndex: Int = 0

    private let po7 = 5
    private let po8 = 7

    func start() {
        stop()
        isConnected = true
        qualityOK = true
        t0 = ProcessInfo.processInfo.systemUptime
        buffer = Array(repeating: [], count: 8)
        times = []
        sampleCount = 0
        tickIndex = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / sampleRate, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isConnected = false
    }

    func setContext(cueSide: Side?, multiplier: Double) {
        self.cueSide = cueSide
        self.multiplier = multiplier
    }

    func window(from start: TimeInterval, to end: TimeInterval) -> EEGWindow {
        var out: [[Double]] = Array(repeating: [], count: 8)
        for (i, t) in times.enumerated() {
            guard t >= start && t <= end else { continue }
            for ch in 0..<8 {
                if i < buffer[ch].count {
                    out[ch].append(buffer[ch][i])
                }
            }
        }
        return EEGWindow(sampleRate: sampleRate, startTime: start, endTime: end, samples: out, source: .mock)
    }

    /// Public so docs/tests can cite the same curve.
    static func responseGain(multiplier m: Double) -> Double {
        exp(-pow((m - demoOptimumMultiplier) / 0.22, 2))
    }

    private func tick() {
        let t = ProcessInfo.processInfo.systemUptime
        times.append(t)
        tickIndex += 1
        let keep = Int(sampleRate * 10)
        if times.count > keep {
            let drop = times.count - keep
            times.removeFirst(drop)
            for ch in 0..<8 { if buffer[ch].count > drop { buffer[ch].removeFirst(drop) } }
        }

        let phase = 2 * Double.pi * 10 * (t - t0)
        let base = 8.0
        let gain = Self.responseGain(multiplier: multiplier)
        var leftBoost = 0.0
        var rightBoost = 0.0
        if cueSide == .left {
            leftBoost = -2.0 * gain
            rightBoost = 3.0 * gain
        } else if cueSide == .right {
            leftBoost = 3.0 * gain
            rightBoost = -2.0 * gain
        }

        for ch in 0..<8 {
            var v = base * sin(phase + Double(ch) * 0.2)
            if ch == po7 { v += leftBoost * sin(phase) }
            if ch == po8 { v += rightBoost * sin(phase) }
            buffer[ch].append(v)
        }
        sampleCount += 1
    }
}

import Foundation

/// Labeled mock EEG stream for Mac demos. Synthesizes PO7/PO8 alpha that responds to
/// attend-side and left-contrast multiplier so the grid search has a known peak (~1.15).
final class MockEEGSource: EEGSource {
    let sourceKind: EEGSourceKind = .mock
    private(set) var isConnected = false
    private(set) var qualityOK = true
    private(set) var sampleCount = 0

    private let sampleRate: Double = 250
    private var buffer: [[Double]] = Array(repeating: [], count: 8)
    private var times: [TimeInterval] = []
    private var timer: Timer?
    private var cueSide: Side?
    private var multiplier: Double = 1.0
    private var t0: TimeInterval = 0

    // Channel indices
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

    private func tick() {
        let t = ProcessInfo.processInfo.systemUptime
        times.append(t)
        // Keep ~10 s of buffer
        let keep = Int(sampleRate * 10)
        if times.count > keep {
            let drop = times.count - keep
            times.removeFirst(drop)
            for ch in 0..<8 { if buffer[ch].count > drop { buffer[ch].removeFirst(drop) } }
        }

        // Synthetic 10 Hz alpha with lateralization biased by cue + multiplier.
        let phase = 2 * Double.pi * 10 * (t - t0)
        let base = 8.0
        // Known mock optimum near 1.15: response strength peaks there.
        let responseGain = exp(-pow((multiplier - 1.15) / 0.22, 2))
        var leftBoost = 0.0
        var rightBoost = 0.0
        if cueSide == .left {
            // Attend-left → relatively lower ipsilateral (PO7) alpha / higher contralateral pattern
            // We encode as higher PO8 vs PO7 when attending left (positive lat).
            leftBoost = -1.5 * responseGain
            rightBoost = 2.0 * responseGain
        } else if cueSide == .right {
            leftBoost = 2.0 * responseGain
            rightBoost = -1.5 * responseGain
        }

        for ch in 0..<8 {
            var v = base * sin(phase + Double(ch) * 0.2) + Double.random(in: -0.3...0.3)
            if ch == po7 { v += leftBoost * sin(phase) }
            if ch == po8 { v += rightBoost * sin(phase) }
            buffer[ch].append(v)
        }
        sampleCount += 1
    }
}

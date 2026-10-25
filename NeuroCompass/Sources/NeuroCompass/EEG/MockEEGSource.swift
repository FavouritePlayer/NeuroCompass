import Foundation

/// Labeled **mock** EEG stream (Mac default). Never reports `live`.
///
/// ## Deterministic demo bias (sound-angle mode)
/// Response gain peaks at HRTF angle **−45°**:
/// `gain = exp(-((angleDeg - (-45)) / 18)^2)` for sound angles;
/// **no-sound** (`angleDeg == 0`) → gain = 0 (flat laterality swing).
///
/// Mock attend-L / attend-R swing is tied to **trial condition side** (`cueSide`),
/// which equals the **dot side** when a target is present — **not** a visible arrow.
/// Left → PO8 > PO7 (positive lat); right → negative lat.
/// Modulation = mean(lat|L) − mean(lat|R) is therefore **largest near −45°**.
final class MockEEGSource: EEGSource {
    let sourceKind: EEGSourceKind = .mock
    private(set) var isConnected = false
    private(set) var qualityOK = true
    private(set) var sampleCount = 0

    static let demoOptimumAngleDeg: Double = SoundAngle.demoOptimum
    /// Deprecated name — same as demoOptimumAngleDeg.
    static let demoOptimumMultiplier: Double = SoundAngle.demoOptimum

    private let sampleRate: Double = 250
    private var buffer: [[Double]] = Array(repeating: [], count: 8)
    private var times: [TimeInterval] = []
    private var timer: Timer?
    private var cueSide: Side?
    /// HRTF azimuth; 0 = no-sound.
    private var soundAngleDeg: Double = SoundAngle.none
    private var t0: TimeInterval = 0

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
        // `multiplier` argument is now soundAngleDeg (0 = no-sound).
        self.cueSide = cueSide
        self.soundAngleDeg = multiplier
    }

    func setContext(cueSide: Side?, soundAngleDeg: Double) {
        self.cueSide = cueSide
        self.soundAngleDeg = soundAngleDeg
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

    static func responseGain(soundAngleDeg a: Double) -> Double {
        if SoundAngle.isNone(a) { return 0 }
        return exp(-pow((a - demoOptimumAngleDeg) / 18.0, 2))
    }

    /// Back-compat name used by older call sites.
    static func responseGain(multiplier m: Double) -> Double {
        responseGain(soundAngleDeg: m)
    }

    private func tick() {
        let t = ProcessInfo.processInfo.systemUptime
        times.append(t)
        let keep = Int(sampleRate * 10)
        if times.count > keep {
            let drop = times.count - keep
            times.removeFirst(drop)
            for ch in 0..<8 { if buffer[ch].count > drop { buffer[ch].removeFirst(drop) } }
        }

        let phase = 2 * Double.pi * 10 * (t - t0)
        let base = 8.0
        let gain = Self.responseGain(soundAngleDeg: soundAngleDeg)
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

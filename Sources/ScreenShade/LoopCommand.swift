import Foundation

/// IPC payload written by NeuroCompass (and other drivers) for the calibration loop.
/// File: `~/Library/Application Support/ScreenShade/loop.json`
///
/// ScreenShade polls this file and maps `leftContrastMultiplier` onto the shared
/// left-side contrast channel (angle 0°, start = left). Other metrics are left alone.
struct LoopCommand: Equatable, Codable {
    /// Relative left-side contrast. 1.0 = neutral, &lt;1 degrades left, &gt;1 boosts left.
    var leftContrastMultiplier: Double = 1.0
    /// When false, overlay may stay up but loop-driven contrast is cleared to neutral.
    var enabled: Bool = true
    var updatedAt: String?

    static let fileName = "loop.json"

    static var url: URL {
        ShadeSettings.supportDirectory.appendingPathComponent(fileName)
    }

    /// Map multiplier → ShadeSettings contrast/dim for a visible left-sided effect.
    func appliedSettings(onto base: ShadeSettings) -> ShadeSettings {
        var s = base
        let m = min(max(leftContrastMultiplier, 0.5), 1.5)
        s.enabled = enabled
        s.angleDegrees = 0
        s.center = 0.5
        s.inverted = false
        s.applyTransitionMode(.short)

        // Contrast channel: left (start) = (m - 1) * 2, right unchanged.
        var contrast = s.contrast
        contrast.enabled = true
        contrast.start = min(max((m - 1.0) * 2.0, -1), 1)
        contrast.end = 0
        s.contrast = contrast

        // Capture-free visual fallback: dim the left when m < 1 (degraded).
        s.brightOpacity = max(0, (1.0 - m) * 0.55)
        s.dimOpacity = 0

        // Leave sat/sharp/warmth as-is (loop does not touch them).
        return s
    }
}

/// Polls `loop.json` and pushes changes into ShadeSettingsStore.
final class LoopCommandWatcher {
    private var timer: Timer?
    private var lastData: Data?
    private(set) var lastCommand: LoopCommand?

    func start() {
        try? FileManager.default.createDirectory(at: ShadeSettings.supportDirectory, withIntermediateDirectories: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let url = LoopCommand.url
        guard let data = try? Data(contentsOf: url) else { return }
        guard data != lastData else { return }
        lastData = data
        guard let command = try? JSONDecoder().decode(LoopCommand.self, from: data) else { return }
        lastCommand = command
        let next = command.appliedSettings(onto: ShadeSettingsStore.shared.settings)
        ShadeSettingsStore.shared.replace(next)
    }
}

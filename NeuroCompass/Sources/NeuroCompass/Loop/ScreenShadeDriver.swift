import Foundation

/// Writes `~/Library/Application Support/ScreenShade/loop.json` for ScreenShade's LoopCommandWatcher.
final class ScreenShadeDriver {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ScreenShade", isDirectory: true)
    }

    var loopURL: URL { supportDirectory.appendingPathComponent("loop.json") }

    func apply(leftContrastMultiplier: Double, enabled: Bool = true) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "leftContrastMultiplier": leftContrastMultiplier,
            "enabled": enabled,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: loopURL, options: .atomic)
        }
    }

    func setNeutral() {
        apply(leftContrastMultiplier: 1.0, enabled: true)
    }
}

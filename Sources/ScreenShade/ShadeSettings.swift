import Foundation
import AppKit

/// How the bright↔dim boundary falls off across the screen.
enum TransitionMode: String, Codable, CaseIterable {
    /// Sharp cutoff (step edge) between bright and dim.
    case hard
    /// Narrow soft ramp.
    case short
    /// Wide soft ramp across much of the screen.
    case long
    /// User-dialed continuous transition width.
    case custom

    var displayName: String {
        switch self {
        case .hard: return "Hard"
        case .short: return "Short"
        case .long: return "Long"
        case .custom: return "Custom"
        }
    }

    /// Preset transition width (0 = hard step, 1 = full-screen ramp).
    var presetWidth: Double {
        switch self {
        case .hard: return 0
        case .short: return 0.12
        case .long: return 0.75
        case .custom: return 0.35
        }
    }

    static func nearest(to width: Double) -> TransitionMode {
        let clamped = min(max(width, 0), 1)
        let candidates: [TransitionMode] = [.hard, .short, .long]
        return candidates.min(by: { abs($0.presetWidth - clamped) < abs($1.presetWidth - clamped) }) ?? .custom
    }
}

/// Controllable parameters for the nonuniform shade overlay.
struct ShadeSettings: Equatable, Codable {
    /// When false, overlay windows are hidden.
    var enabled: Bool = true

    /// Gradient axis in degrees. 0° = left→right (start → end), 90° = top→bottom.
    var angleDegrees: Double = 0

    /// Position of the bright/dark transition along the axis, 0…1.
    var center: Double = 0.5

    /// Overlay opacity on the bright side (0 = no dimming).
    var brightOpacity: Double = 0.0

    /// Overlay opacity on the dim side (higher = darker).
    var dimOpacity: Double = 0.55

    /// Falloff mode: hard / short / long presets, or custom width.
    var transitionMode: TransitionMode = .short

    /// Continuous transition width / step size, 0 (hard) … 1 (longest).
    /// Preset modes set this; dragging the slider switches mode to `.custom`
    /// unless the value lands exactly on a preset.
    var transitionWidth: Double = TransitionMode.short.presetWidth

    /// Swap bright and dim sides without changing angle.
    var inverted: Bool = false

    static let defaultsKey = "shadeSettings"
    static let configFileName = "config.json"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ScreenShade", isDirectory: true)
    }

    static var configURL: URL {
        supportDirectory.appendingPathComponent(configFileName)
    }

    /// Effective width used for color stops (respects mode presets).
    var effectiveTransitionWidth: Double {
        switch transitionMode {
        case .hard, .short, .long:
            return transitionMode.presetWidth
        case .custom:
            return transitionWidth
        }
    }

    mutating func applyTransitionMode(_ mode: TransitionMode) {
        transitionMode = mode
        if mode != .custom {
            transitionWidth = mode.presetWidth
        }
    }

    /// After the user moves the width slider, snap to a named mode or mark custom.
    mutating func applyTransitionWidth(_ width: Double) {
        let w = min(max(width, 0), 1)
        transitionWidth = w
        let epsilon = 0.02
        if abs(w - TransitionMode.hard.presetWidth) <= epsilon {
            transitionMode = .hard
            transitionWidth = TransitionMode.hard.presetWidth
        } else if abs(w - TransitionMode.short.presetWidth) <= epsilon {
            transitionMode = .short
            transitionWidth = TransitionMode.short.presetWidth
        } else if abs(w - TransitionMode.long.presetWidth) <= epsilon {
            transitionMode = .long
            transitionWidth = TransitionMode.long.presetWidth
        } else {
            transitionMode = .custom
        }
    }

    mutating func clamp() {
        center = min(max(center, 0), 1)
        brightOpacity = min(max(brightOpacity, 0), 0.95)
        dimOpacity = min(max(dimOpacity, 0), 0.95)
        transitionWidth = min(max(transitionWidth, 0), 1)
        var a = angleDegrees.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        angleDegrees = a
        // Keep width aligned with named presets.
        if transitionMode != .custom {
            transitionWidth = transitionMode.presetWidth
        }
    }

    /// Start/end colors for a black overlay gradient (alpha = opacity).
    func gradientColors() -> (start: NSColor, end: NSColor) {
        let bright = inverted ? dimOpacity : brightOpacity
        let dim = inverted ? brightOpacity : dimOpacity
        return (
            NSColor(white: 0, alpha: CGFloat(bright)),
            NSColor(white: 0, alpha: CGFloat(dim))
        )
    }

    /// Color-stop locations for center + effective transition width.
    func colorLocations() -> [NSNumber] {
        let width = effectiveTransitionWidth
        // Hard / near-hard: tiny epsilon so CAGradientLayer still draws a step.
        if width <= 0.001 {
            let c = min(max(center, 0.001), 0.999)
            return [0, NSNumber(value: c), NSNumber(value: c), 1]
        }
        let half = width * 0.5
        let left = max(0, center - half)
        let right = min(1, center + half)
        if left >= right {
            let c = min(max(center, 0.001), 0.999)
            return [0, NSNumber(value: c), NSNumber(value: c), 1]
        }
        return [0, NSNumber(value: left), NSNumber(value: right), 1]
    }

    func colorsForStops() -> [NSColor] {
        let (start, end) = gradientColors()
        return [start, start, end, end]
    }

    /// Unit vector of the gradient direction (AppKit y-up for layer start/end points).
    func directionVector() -> CGPoint {
        let rad = angleDegrees * .pi / 180
        return CGPoint(x: cos(rad), y: -sin(rad))
    }

    /// CAGradientLayer start/end points in unit space for the given angle.
    func gradientPoints() -> (start: CGPoint, end: CGPoint) {
        let d = directionVector()
        let start = CGPoint(x: 0.5 - d.x * 0.5, y: 0.5 - d.y * 0.5)
        let end = CGPoint(x: 0.5 + d.x * 0.5, y: 0.5 + d.y * 0.5)
        return (start, end)
    }

    // Migrate older configs that used `softness` instead of transition fields.
    enum CodingKeys: String, CodingKey {
        case enabled, angleDegrees, center, brightOpacity, dimOpacity
        case transitionMode, transitionWidth, inverted, softness
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        angleDegrees = try c.decodeIfPresent(Double.self, forKey: .angleDegrees) ?? 0
        center = try c.decodeIfPresent(Double.self, forKey: .center) ?? 0.5
        brightOpacity = try c.decodeIfPresent(Double.self, forKey: .brightOpacity) ?? 0
        dimOpacity = try c.decodeIfPresent(Double.self, forKey: .dimOpacity) ?? 0.55
        inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? false

        if let mode = try c.decodeIfPresent(TransitionMode.self, forKey: .transitionMode) {
            transitionMode = mode
            transitionWidth = try c.decodeIfPresent(Double.self, forKey: .transitionWidth) ?? mode.presetWidth
        } else if let soft = try c.decodeIfPresent(Double.self, forKey: .softness) {
            // Map legacy softness → custom width.
            transitionWidth = soft
            transitionMode = TransitionMode.nearest(to: soft)
            if abs(transitionMode.presetWidth - soft) > 0.02 {
                transitionMode = .custom
            }
        } else {
            transitionMode = .short
            transitionWidth = TransitionMode.short.presetWidth
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(angleDegrees, forKey: .angleDegrees)
        try c.encode(center, forKey: .center)
        try c.encode(brightOpacity, forKey: .brightOpacity)
        try c.encode(dimOpacity, forKey: .dimOpacity)
        try c.encode(transitionMode, forKey: .transitionMode)
        try c.encode(transitionWidth, forKey: .transitionWidth)
        try c.encode(inverted, forKey: .inverted)
    }
}

final class ShadeSettingsStore {
    static let shared = ShadeSettingsStore()

    private let defaults = UserDefaults.standard
    private(set) var settings: ShadeSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
            NotificationCenter.default.post(name: .shadeSettingsDidChange, object: settings)
        }
    }

    private init() {
        if let loaded = Self.loadFromDisk() {
            settings = loaded
        } else if let data = defaults.data(forKey: ShadeSettings.defaultsKey),
                  let decoded = try? JSONDecoder().decode(ShadeSettings.self, from: data) {
            settings = decoded
        } else {
            settings = ShadeSettings()
        }
        settings.clamp()
    }

    func update(_ mutate: (inout ShadeSettings) -> Void) {
        var next = settings
        mutate(&next)
        next.clamp()
        settings = next
    }

    func replace(_ next: ShadeSettings) {
        var copy = next
        copy.clamp()
        settings = copy
    }

    func reloadFromDisk() {
        if let loaded = Self.loadFromDisk() {
            replace(loaded)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: ShadeSettings.defaultsKey)
        }
        try? FileManager.default.createDirectory(at: ShadeSettings.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: ShadeSettings.configURL, options: .atomic)
        }
    }

    private static func loadFromDisk() -> ShadeSettings? {
        let urls = [
            ShadeSettings.configURL,
            Bundle.main.resourceURL?.appendingPathComponent("config.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("config/config.json")
        ].compactMap { $0 }

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  var decoded = try? JSONDecoder().decode(ShadeSettings.self, from: data) else { continue }
            decoded.clamp()
            return decoded
        }
        return nil
    }
}

extension Notification.Name {
    static let shadeSettingsDidChange = Notification.Name("ShadeSettingsDidChange")
}

import Foundation
import AppKit

/// How the bright↔dim boundary falls off across the screen.
enum TransitionMode: String, Codable, CaseIterable {
    case hard
    case short
    case long
    case custom

    var displayName: String {
        switch self {
        case .hard: return "Hard"
        case .short: return "Short"
        case .long: return "Long"
        case .custom: return "Custom"
        }
    }

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

/// One metric mapped across the shared gradient (start = bright side, end = dim side).
struct MetricChannel: Equatable, Codable {
    var enabled: Bool = false
    /// Amount on the bright / start side of the gradient.
    var start: Double = 0
    /// Amount on the dim / end side of the gradient.
    var end: Double = 0

    static func disabled(start: Double = 0, end: Double = 0) -> MetricChannel {
        MetricChannel(enabled: false, start: start, end: end)
    }

    mutating func clamp(minValue: Double, maxValue: Double) {
        start = min(max(start, minValue), maxValue)
        end = min(max(end, minValue), maxValue)
    }
}

/// Controllable parameters for the nonuniform shade overlay.
///
/// **Geometry model:** one shared gradient (angle, center/split, transition mode/width, invert)
/// drives every enabled metric — dimming, contrast, saturation, sharpness, and warmth.
struct ShadeSettings: Equatable, Codable {
    var enabled: Bool = true

    // MARK: Shared gradient geometry
    var angleDegrees: Double = 0
    var center: Double = 0.5
    var transitionMode: TransitionMode = .short
    var transitionWidth: Double = TransitionMode.short.presetWidth
    var inverted: Bool = false

    // MARK: Dimming (cheap path; no screen capture)
    /// Overlay opacity on the bright side (0 = no dimming).
    var brightOpacity: Double = 0.0
    /// Overlay opacity on the dim side (higher = darker).
    var dimOpacity: Double = 0.55

    // MARK: Advanced metrics (ScreenCaptureKit + Core Image; shared geometry)
    /// Contrast: -1…1 (0 = unchanged). Needs screen capture.
    var contrast: MetricChannel = .disabled(start: 0, end: 0.35)
    /// Saturation: -1…1 (0 = unchanged). Needs screen capture.
    var saturation: MetricChannel = .disabled(start: 0, end: -0.45)
    /// Sharpness: -1…1 (negative = soften/blur, positive = sharpen). Needs screen capture.
    var sharpness: MetricChannel = .disabled(start: 0, end: 0.4)
    /// Warmth: -1…1 (cool ↔ warm). Needs screen capture. Optional bonus metric.
    var warmth: MetricChannel = .disabled(start: 0, end: 0.25)

    static let defaultsKey = "shadeSettings"
    static let configFileName = "config.json"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ScreenShade", isDirectory: true)
    }

    static var configURL: URL {
        supportDirectory.appendingPathComponent(configFileName)
    }

    /// True when any metric requires capturing and filtering the display.
    var needsScreenCapture: Bool {
        contrast.enabled || saturation.enabled || sharpness.enabled || warmth.enabled
    }

    var effectiveTransitionWidth: Double {
        switch transitionMode {
        case .hard, .short, .long: return transitionMode.presetWidth
        case .custom: return transitionWidth
        }
    }

    /// Start/end amounts for a channel, respecting invert (swap sides).
    func oriented(_ channel: MetricChannel) -> (start: Double, end: Double) {
        inverted ? (channel.end, channel.start) : (channel.start, channel.end)
    }

    func orientedDimOpacities() -> (start: Double, end: Double) {
        inverted ? (dimOpacity, brightOpacity) : (brightOpacity, dimOpacity)
    }

    mutating func applyTransitionMode(_ mode: TransitionMode) {
        transitionMode = mode
        if mode != .custom {
            transitionWidth = mode.presetWidth
        }
    }

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
        contrast.clamp(minValue: -1, maxValue: 1)
        saturation.clamp(minValue: -1, maxValue: 1)
        sharpness.clamp(minValue: -1, maxValue: 1)
        warmth.clamp(minValue: -1, maxValue: 1)
        var a = angleDegrees.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        angleDegrees = a
        if transitionMode != .custom {
            transitionWidth = transitionMode.presetWidth
        }
    }

    func gradientColors() -> (start: NSColor, end: NSColor) {
        let (bright, dim) = orientedDimOpacities()
        return (
            NSColor(white: 0, alpha: CGFloat(bright)),
            NSColor(white: 0, alpha: CGFloat(dim))
        )
    }

    func colorLocations() -> [NSNumber] {
        let width = effectiveTransitionWidth
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

    /// Mask stops: black (0) on start/bright side → white (1) on end/dim side.
    func maskColorsForStops() -> [NSColor] {
        [
            NSColor(white: 0, alpha: 1),
            NSColor(white: 0, alpha: 1),
            NSColor(white: 1, alpha: 1),
            NSColor(white: 1, alpha: 1)
        ]
    }

    func directionVector() -> CGPoint {
        let rad = angleDegrees * .pi / 180
        return CGPoint(x: cos(rad), y: -sin(rad))
    }

    func gradientPoints() -> (start: CGPoint, end: CGPoint) {
        let d = directionVector()
        let start = CGPoint(x: 0.5 - d.x * 0.5, y: 0.5 - d.y * 0.5)
        let end = CGPoint(x: 0.5 + d.x * 0.5, y: 0.5 + d.y * 0.5)
        return (start, end)
    }

    enum CodingKeys: String, CodingKey {
        case enabled, angleDegrees, center, brightOpacity, dimOpacity
        case transitionMode, transitionWidth, inverted, softness
        case contrast, saturation, sharpness, warmth
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
        contrast = try c.decodeIfPresent(MetricChannel.self, forKey: .contrast) ?? .disabled(start: 0, end: 0.35)
        saturation = try c.decodeIfPresent(MetricChannel.self, forKey: .saturation) ?? .disabled(start: 0, end: -0.45)
        sharpness = try c.decodeIfPresent(MetricChannel.self, forKey: .sharpness) ?? .disabled(start: 0, end: 0.4)
        warmth = try c.decodeIfPresent(MetricChannel.self, forKey: .warmth) ?? .disabled(start: 0, end: 0.25)

        if let mode = try c.decodeIfPresent(TransitionMode.self, forKey: .transitionMode) {
            transitionMode = mode
            transitionWidth = try c.decodeIfPresent(Double.self, forKey: .transitionWidth) ?? mode.presetWidth
        } else if let soft = try c.decodeIfPresent(Double.self, forKey: .softness) {
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
        try c.encode(contrast, forKey: .contrast)
        try c.encode(saturation, forKey: .saturation)
        try c.encode(sharpness, forKey: .sharpness)
        try c.encode(warmth, forKey: .warmth)
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
    static let shadeCapturePermissionDidChange = Notification.Name("ShadeCapturePermissionDidChange")
}

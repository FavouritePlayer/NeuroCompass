import AppKit
import QuartzCore

/// Full-window view that draws a configurable black alpha gradient for nonuniform dimming.
final class GradientOverlayView: NSView {
    private let gradientLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.5).cgColor
        ]
        layer?.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    func apply(_ settings: ShadeSettings) {
        let colors = settings.colorsForStops()
        gradientLayer.colors = colors.map { $0.cgColor }
        gradientLayer.locations = settings.colorLocations()
        let points = settings.gradientPoints()
        gradientLayer.startPoint = points.start
        gradientLayer.endPoint = points.end
        // Smooth interpolation looks better for soft falloff.
        gradientLayer.type = .axial
    }
}

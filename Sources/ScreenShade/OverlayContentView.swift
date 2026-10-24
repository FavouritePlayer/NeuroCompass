import AppKit
import QuartzCore

/// Hosts either the cheap dimming gradient or a filtered screen-capture image.
final class OverlayContentView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let imageLayer = CALayer()
    private var currentSettings = ShadeSettings()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        gradientLayer.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.5).cgColor]
        layer?.addSublayer(gradientLayer)

        imageLayer.contentsGravity = .resize
        imageLayer.isHidden = true
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        imageLayer.frame = bounds
    }

    func apply(_ settings: ShadeSettings) {
        currentSettings = settings
        let capture = settings.needsScreenCapture
        gradientLayer.isHidden = capture
        imageLayer.isHidden = !capture

        if !capture {
            imageLayer.contents = nil
            let colors = settings.colorsForStops()
            gradientLayer.colors = colors.map(\.cgColor)
            gradientLayer.locations = settings.colorLocations()
            let points = settings.gradientPoints()
            gradientLayer.startPoint = points.start
            gradientLayer.endPoint = points.end
            gradientLayer.type = .axial
        }
    }

    func showFilteredFrame(_ image: CGImage) {
        guard currentSettings.needsScreenCapture else { return }
        imageLayer.contents = image
        imageLayer.isHidden = false
        gradientLayer.isHidden = true
    }

    func clearFilteredFrame() {
        imageLayer.contents = nil
    }
}

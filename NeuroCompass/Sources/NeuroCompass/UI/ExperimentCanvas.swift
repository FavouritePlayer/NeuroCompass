import AppKit

/// Timing-critical stimulus surface.
/// Participant task: watch the cross; optional HRTF chirp; report which side the **dot** flashed.
/// No attention arrow. Sound angle badge for the operator; veil unused.
final class ExperimentCanvas: NSView {
    private(set) var phase: TrialPhase = .idle {
        didSet { needsDisplay = true }
    }

    /// 0 = no-sound; otherwise HRTF azimuth degrees.
    private(set) var soundAngleDeg: Double = SoundAngle.none {
        didSet { needsDisplay = true }
    }

    static let instruction =
        "A sound may play. Watch the cross. When a dot flashes, press F (left) or J (right)."

    func setPhase(_ phase: TrialPhase) {
        self.phase = phase
    }

    func setSoundAngleDeg(_ deg: Double) {
        soundAngleDeg = deg
    }

    /// Left unused — darkness veil disabled in sound mode.
    func setLeftContrastMultiplier(_ m: Double) {}

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        let cx = bounds.midX
        let cy = bounds.midY
        let ecc: CGFloat = min(bounds.width, bounds.height) * 0.28

        switch phase {
        case .idle:
            drawCenteredText("NeuroCompass — HRTF sound calibration (mock EEG)", color: .secondaryLabelColor)
            drawInstruction(emphasized: true)
            drawAngleBadge()
        case .fixation, .waitForDot:
            drawFixation(at: CGPoint(x: cx, y: cy))
            drawInstruction(emphasized: false)
            drawAngleBadge()
        case .target(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            if let side {
                let x = side == .left ? cx - ecc : cx + ecc
                drawTarget(at: CGPoint(x: x, y: cy))
            }
            drawInstruction(emphasized: false)
            drawAngleBadge()
        case .response:
            drawFixation(at: CGPoint(x: cx, y: cy))
            drawKeyHints()
            drawInstruction(emphasized: true)
            drawAngleBadge()
        case .feedback(let msg):
            drawCenteredText(msg, color: .white, fontSize: 48)
            drawInstruction(emphasized: false)
            drawAngleBadge()
        case .interTrial:
            drawInstruction(emphasized: false)
            drawAngleBadge()
        }
    }

    private func drawInstruction(emphasized: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: emphasized ? 15 : 13, weight: emphasized ? .semibold : .regular),
            .foregroundColor: emphasized ? NSColor.white : NSColor.secondaryLabelColor
        ]
        let s = Self.instruction as NSString
        let size = s.size(withAttributes: attrs)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: 28)
        s.draw(at: origin, withAttributes: attrs)
    }

    private func drawKeyHints() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor.systemYellow
        ]
        let s = "F = left     J = right" as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - 140), withAttributes: attrs)
    }

    private func drawAngleBadge() {
        let label = "sound: \(SoundAngle.label(soundAngleDeg))  ·  eeg: mock"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemYellow
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(at: CGPoint(x: 12, y: bounds.maxY - size.height - 12), withAttributes: attrs)
    }

    private func drawFixation(at p: CGPoint) {
        let len: CGFloat = 14
        let path = NSBezierPath()
        path.move(to: CGPoint(x: p.x - len, y: p.y))
        path.line(to: CGPoint(x: p.x + len, y: p.y))
        path.move(to: CGPoint(x: p.x, y: p.y - len))
        path.line(to: CGPoint(x: p.x, y: p.y + len))
        NSColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func drawTarget(at p: CGPoint) {
        let r: CGFloat = 12
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
    }

    private func drawCenteredText(_ string: String, color: NSColor, fontSize: CGFloat = 18, yOffset: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color
        ]
        let size = (string as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 + yOffset)
        (string as NSString).draw(at: origin, withAttributes: attrs)
    }
}

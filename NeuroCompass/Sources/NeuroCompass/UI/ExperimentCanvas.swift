import AppKit

/// Timing-critical stimulus surface. Same NeuroCompass look; shows active **sound angle**
/// (no left-contrast veil — calibrated parameter is HRTF azimuth).
final class ExperimentCanvas: NSView {
    private(set) var phase: TrialPhase = .idle {
        didSet { needsDisplay = true }
    }

    /// 0 = no-sound; otherwise HRTF azimuth degrees.
    private(set) var soundAngleDeg: Double = SoundAngle.none {
        didSet { needsDisplay = true }
    }

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
            drawAngleBadge()
        case .fixation, .anticipatory:
            drawFixation(at: CGPoint(x: cx, y: cy))
            drawAngleBadge()
        case .cue(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            drawCenteredText(side == .left ? "←" : "→", color: .white, fontSize: 64, yOffset: 80)
            drawAngleBadge()
        case .target(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            if let side {
                let x = side == .left ? cx - ecc : cx + ecc
                drawTarget(at: CGPoint(x: x, y: cy))
            }
            drawAngleBadge()
        case .response:
            drawFixation(at: CGPoint(x: cx, y: cy))
            drawCenteredText("f = left · j = right", color: .systemGray, fontSize: 16, yOffset: -120)
            drawAngleBadge()
        case .feedback(let msg):
            drawCenteredText(msg, color: .white, fontSize: 48)
            drawAngleBadge()
        case .interTrial:
            drawAngleBadge()
        }
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

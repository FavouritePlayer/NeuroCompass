import AppKit

/// Timing-critical stimulus surface (fixation, cue, target). Own window only.
final class ExperimentCanvas: NSView {
    private(set) var phase: TrialPhase = .idle {
        didSet { needsDisplay = true }
    }

    func setPhase(_ phase: TrialPhase) {
        self.phase = phase
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        let cx = bounds.midX
        let cy = bounds.midY
        let ecc: CGFloat = min(bounds.width, bounds.height) * 0.28

        switch phase {
        case .idle:
            drawCenteredText("NeuroCompass — press Start Calibration or Run Block", color: .secondaryLabelColor)
        case .fixation, .anticipatory:
            drawFixation(at: CGPoint(x: cx, y: cy))
        case .cue(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            let arrow = side == .left ? "←" : "→"
            drawCenteredText(arrow, color: .white, fontSize: 64, yOffset: 80)
        case .target(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            if let side {
                let x = side == .left ? cx - ecc : cx + ecc
                drawTarget(at: CGPoint(x: x, y: cy))
            }
        case .response(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            if let side {
                let x = side == .left ? cx - ecc : cx + ecc
                // Target gone; keep faint placeholder rings optional — leave blank for response.
                _ = x
            }
            drawCenteredText("f = left · j = right", color: .systemGray, fontSize: 16, yOffset: -120)
        case .feedback(let msg):
            drawCenteredText(msg, color: .white, fontSize: 48)
        case .interTrial:
            break
        }
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
        let r: CGFloat = 10
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
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

import AppKit

/// Timing-critical stimulus surface (fixation, cue, target). Own window only.
/// Left-side contrast disadvantage is rendered **in-window** from `leftContrastMultiplier`
/// (not a system overlay). Right half is never veiled.
final class ExperimentCanvas: NSView {
    private(set) var phase: TrialPhase = .idle {
        didSet { needsDisplay = true }
    }

    /// 1.0 = neutral (no left hit). &lt;1 = left contrast reduced. &gt;1 = left unshaded (boost vs degraded).
    private(set) var leftContrastMultiplier: Double = 1.0 {
        didSet { needsDisplay = true }
    }

    func setPhase(_ phase: TrialPhase) {
        self.phase = phase
    }

    func setLeftContrastMultiplier(_ m: Double) {
        leftContrastMultiplier = min(max(m, 0.5), 1.5)
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        let cx = bounds.midX
        let cy = bounds.midY
        let ecc: CGFloat = min(bounds.width, bounds.height) * 0.28
        let m = leftContrastMultiplier

        // Draw stimuli first; left veil applied afterward so only the left hemifield is hit.
        switch phase {
        case .idle:
            drawHemifieldGuides()
            drawCenteredText("NeuroCompass — press Start Calibration or Run Block", color: .secondaryLabelColor)
            drawMultiplierBadge()
        case .fixation, .anticipatory:
            drawFixation(at: CGPoint(x: cx, y: cy))
            drawMultiplierBadge()
        case .cue(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            let arrow = side == .left ? "←" : "→"
            // Cue glyph sits above fixation (center); keep full luminance — side cue is symbolic.
            drawCenteredText(arrow, color: .white, fontSize: 64, yOffset: 80)
            drawMultiplierBadge()
        case .target(let side):
            drawFixation(at: CGPoint(x: cx, y: cy))
            if let side {
                let x = side == .left ? cx - ecc : cx + ecc
                // Left targets use reduced fill when m < 1; right targets always full white.
                let color: NSColor = side == .left ? leftStimulusColor(m) : .white
                drawTarget(at: CGPoint(x: x, y: cy), color: color)
            }
            drawMultiplierBadge()
        case .response:
            drawFixation(at: CGPoint(x: cx, y: cy))
            drawCenteredText("f = left · j = right", color: .systemGray, fontSize: 16, yOffset: -120)
            drawMultiplierBadge()
        case .feedback(let msg):
            drawCenteredText(msg, color: .white, fontSize: 48)
            drawMultiplierBadge()
        case .interTrial:
            drawMultiplierBadge()
        }

        applyLeftContrastVeil(multiplier: m)
    }

    /// Left-hemifield veil: reduces apparent contrast of everything on the left of midX.
    /// Right hemifield is untouched (design A9).
    private func applyLeftContrastVeil(multiplier m: Double) {
        guard m < 0.999 else { return }
        // Stronger degradation as m drops below 1 (e.g. 0.85 → ~0.55 opacity).
        let alpha = min(0.85, (1.0 - m) * 3.6)
        let left = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.midX - bounds.minX, height: bounds.height)
        NSColor.black.withAlphaComponent(CGFloat(alpha)).setFill()
        left.fill()
    }

    private func leftStimulusColor(_ m: Double) -> NSColor {
        if m >= 1.0 { return .white }
        let g = CGFloat(max(0.25, m))
        return NSColor(white: g, alpha: 1)
    }

    private func drawHemifieldGuides() {
        // Subtle mid-line so the left disadvantage is obvious even before trials.
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
        path.line(to: CGPoint(x: bounds.midX, y: bounds.maxY))
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawMultiplierBadge() {
        let label: String
        if leftContrastMultiplier >= 0.999 && leftContrastMultiplier <= 1.001 {
            label = "in-app shade: neutral ×1.00"
        } else if leftContrastMultiplier < 1.0 {
            label = String(format: "in-app shade: LEFT degraded ×%.2f", leftContrastMultiplier)
        } else {
            label = String(format: "in-app shade: LEFT ×%.2f (no veil)", leftContrastMultiplier)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemYellow
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: 12, y: bounds.maxY - size.height - 12)
        (label as NSString).draw(at: origin, withAttributes: attrs)
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

    private func drawTarget(at p: CGPoint, color: NSColor = .white) {
        let r: CGFloat = 12
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        color.setFill()
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

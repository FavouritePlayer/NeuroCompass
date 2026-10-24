import AppKit

/// Floating settings panel: shared geometry + metric channels.
final class SettingsPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var overlay: OverlayController?

    private var enabledButton: NSButton!
    private var invertedButton: NSButton!
    private var angleSlider: NSSlider!
    private var centerSlider: NSSlider!
    private var brightSlider: NSSlider!
    private var dimSlider: NSSlider!
    private var widthSlider: NSSlider!
    private var modeControl: NSSegmentedControl!
    private var angleLabel: NSTextField!
    private var centerLabel: NSTextField!
    private var brightLabel: NSTextField!
    private var dimLabel: NSTextField!
    private var widthLabel: NSTextField!
    private var modeHintLabel: NSTextField!
    private var permissionLabel: NSTextField!

    private var contrastEnable: NSButton!
    private var contrastStart: NSSlider!
    private var contrastEnd: NSSlider!
    private var contrastStartLabel: NSTextField!
    private var contrastEndLabel: NSTextField!

    private var satEnable: NSButton!
    private var satStart: NSSlider!
    private var satEnd: NSSlider!
    private var satStartLabel: NSTextField!
    private var satEndLabel: NSTextField!

    private var sharpEnable: NSButton!
    private var sharpStart: NSSlider!
    private var sharpEnd: NSSlider!
    private var sharpStartLabel: NSTextField!
    private var sharpEndLabel: NSTextField!

    private var warmEnable: NSButton!
    private var warmStart: NSSlider!
    private var warmEnd: NSSlider!
    private var warmStartLabel: NSTextField!
    private var warmEndLabel: NSTextField!

    private var updating = false
    private let modeOrder: [TransitionMode] = [.hard, .short, .long, .custom]

    init(overlay: OverlayController) {
        self.overlay = overlay
        super.init()
        NotificationCenter.default.addObserver(
            forName: .shadeCapturePermissionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let granted = (note.object as? Bool) ?? false
            self?.permissionLabel?.stringValue = granted
                ? "Screen Recording: granted (capture metrics active)."
                : "Screen Recording: needed for contrast / saturation / sharpness / warmth."
        }
    }

    func show() {
        if panel == nil {
            panel = buildPanel()
        }
        syncFromStore()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    // MARK: - Build

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "ScreenShade"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 380, height: 400)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 560))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let contentHeight: CGFloat = 980
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: contentHeight))
        var y: CGFloat = contentHeight - 28

        enabledButton = checkbox("Enable overlay", action: #selector(toggleEnabled), y: &y, in: content)
        invertedButton = checkbox("Invert bright / dim sides", action: #selector(toggleInverted), y: &y, in: content)

        y -= 4
        sectionTitle("Shared gradient", y: &y, in: content)
        (angleSlider, angleLabel) = labeledSlider("Angle (direction)", 0, 360, 0, #selector(sliderChanged), &y, content)
        (centerSlider, centerLabel) = labeledSlider("Split / center", 0, 1, 0.5, #selector(sliderChanged), &y, content)
        (brightSlider, brightLabel) = labeledSlider("Bright opacity (dim)", 0, 0.95, 0, #selector(sliderChanged), &y, content)
        (dimSlider, dimLabel) = labeledSlider("Dim opacity (strength)", 0, 0.95, 0.55, #selector(sliderChanged), &y, content)

        let modeTitle = NSTextField(labelWithString: "Transition / falloff")
        modeTitle.font = .boldSystemFont(ofSize: 12)
        modeTitle.frame = NSRect(x: 16, y: y, width: 340, height: 18)
        content.addSubview(modeTitle)
        y -= 26

        modeControl = NSSegmentedControl(labels: modeOrder.map(\.displayName), trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
        modeControl.segmentStyle = .rounded
        modeControl.frame = NSRect(x: 16, y: y, width: 348, height: 24)
        content.addSubview(modeControl)
        y -= 22

        modeHintLabel = NSTextField(labelWithString: modeHint(for: .short))
        modeHintLabel.font = .systemFont(ofSize: 10)
        modeHintLabel.textColor = .secondaryLabelColor
        modeHintLabel.frame = NSRect(x: 16, y: y, width: 348, height: 16)
        content.addSubview(modeHintLabel)
        y -= 24

        (widthSlider, widthLabel) = labeledSlider("Transition width", 0, 1, 0.12, #selector(widthChanged), &y, content)

        y -= 4
        sectionTitle("Metric channels (shared geometry)", y: &y, in: content)

        permissionLabel = NSTextField(wrappingLabelWithString: "Screen Recording: needed for contrast / saturation / sharpness / warmth.")
        permissionLabel.font = .systemFont(ofSize: 10)
        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.frame = NSRect(x: 16, y: y - 20, width: 348, height: 32)
        content.addSubview(permissionLabel)
        y -= 40

        (contrastEnable, contrastStart, contrastEnd, contrastStartLabel, contrastEndLabel) =
            metricBlock("Contrast (−1…1)", enableAction: #selector(metricToggled), y: &y, in: content, tag: 1)
        (satEnable, satStart, satEnd, satStartLabel, satEndLabel) =
            metricBlock("Saturation (−1…1)", enableAction: #selector(metricToggled), y: &y, in: content, tag: 2)
        (sharpEnable, sharpStart, sharpEnd, sharpStartLabel, sharpEndLabel) =
            metricBlock("Sharpness (−1 soften … +1 sharpen)", enableAction: #selector(metricToggled), y: &y, in: content, tag: 3)
        (warmEnable, warmStart, warmEnd, warmStartLabel, warmEndLabel) =
            metricBlock("Warmth (−1 cool … +1 warm)", enableAction: #selector(metricToggled), y: &y, in: content, tag: 4)

        let presets = NSStackView()
        presets.orientation = .horizontal
        presets.spacing = 8
        presets.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(presets)
        for (title, action) in [
            ("Left bright", #selector(presetLeftBright)),
            ("Right bright", #selector(presetRightBright)),
            ("Demo metrics", #selector(presetDemoMetrics))
        ] {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            presets.addArrangedSubview(b)
        }
        NSLayoutConstraint.activate([
            presets.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            presets.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])

        let hint = NSTextField(labelWithString: "Config: ~/Library/Application Support/ScreenShade/config.json")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hint.bottomAnchor.constraint(equalTo: presets.topAnchor, constant: -8)
        ])

        scroll.documentView = content
        // Pin content to top of scroll view
        if let doc = scroll.documentView {
            doc.setFrameOrigin(NSPoint(x: 0, y: 0))
        }
        panel.contentView = scroll
        return panel
    }

    private func sectionTitle(_ text: String, y: inout CGFloat, in parent: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        label.frame = NSRect(x: 16, y: y, width: 340, height: 18)
        parent.addSubview(label)
        y -= 26
    }

    private func checkbox(_ title: String, action: Selector, y: inout CGFloat, in parent: NSView) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.frame = NSRect(x: 16, y: y, width: 340, height: 22)
        parent.addSubview(button)
        y -= 28
        return button
    }

    private func labeledSlider(_ title: String, _ minV: Double, _ maxV: Double, _ value: Double, _ action: Selector, _ y: inout CGFloat, _ parent: NSView) -> (NSSlider, NSTextField) {
        let label = NSTextField(labelWithString: "\(title): \(fmt(value))")
        label.frame = NSRect(x: 16, y: y, width: 348, height: 18)
        label.font = .systemFont(ofSize: 12)
        parent.addSubview(label)
        y -= 22
        let slider = NSSlider(value: value, minValue: minV, maxValue: maxV, target: self, action: action)
        slider.frame = NSRect(x: 16, y: y, width: 348, height: 22)
        slider.isContinuous = true
        parent.addSubview(slider)
        y -= 30
        return (slider, label)
    }

    private func metricBlock(
        _ title: String,
        enableAction: Selector,
        y: inout CGFloat,
        in parent: NSView,
        tag: Int
    ) -> (NSButton, NSSlider, NSSlider, NSTextField, NSTextField) {
        let enable = NSButton(checkboxWithTitle: title, target: self, action: enableAction)
        enable.tag = tag
        enable.frame = NSRect(x: 16, y: y, width: 348, height: 22)
        parent.addSubview(enable)
        y -= 24

        let (sSlider, sLabel) = labeledSlider("  Start (bright side)", -1, 1, 0, #selector(sliderChanged), &y, parent)
        let (eSlider, eLabel) = labeledSlider("  End (dim side)", -1, 1, 0, #selector(sliderChanged), &y, parent)
        sSlider.tag = tag * 10
        eSlider.tag = tag * 10 + 1
        return (enable, sSlider, eSlider, sLabel, eLabel)
    }

    private func modeHint(for mode: TransitionMode) -> String {
        switch mode {
        case .hard: return "Hard: sharp cutoff at the split (step edge)."
        case .short: return "Short: narrow soft ramp between regions."
        case .long: return "Long: wide soft ramp across much of the screen."
        case .custom: return "Custom: dial transition width freely."
        }
    }

    private func fmt(_ value: Double) -> String {
        if abs(value) >= 10 || (value == floor(value) && abs(value) >= 1) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    // MARK: - Sync

    private func syncFromStore() {
        updating = true
        defer { updating = false }
        let s = ShadeSettingsStore.shared.settings
        enabledButton.state = s.enabled ? .on : .off
        invertedButton.state = s.inverted ? .on : .off
        angleSlider.doubleValue = s.angleDegrees
        centerSlider.doubleValue = s.center
        brightSlider.doubleValue = s.brightOpacity
        dimSlider.doubleValue = s.dimOpacity
        widthSlider.doubleValue = s.effectiveTransitionWidth
        if let idx = modeOrder.firstIndex(of: s.transitionMode) {
            modeControl.selectedSegment = idx
        }
        modeHintLabel.stringValue = modeHint(for: s.transitionMode)

        syncMetric(s.contrast, contrastEnable, contrastStart, contrastEnd)
        syncMetric(s.saturation, satEnable, satStart, satEnd)
        syncMetric(s.sharpness, sharpEnable, sharpStart, sharpEnd)
        syncMetric(s.warmth, warmEnable, warmStart, warmEnd)

        let granted = overlay?.capturePermissionGranted ?? CGPreflightScreenCaptureAccess()
        permissionLabel.stringValue = granted
            ? "Screen Recording: granted (capture metrics active)."
            : "Screen Recording: needed for contrast / saturation / sharpness / warmth."

        refreshLabels()
    }

    private func syncMetric(_ m: MetricChannel, _ enable: NSButton, _ start: NSSlider, _ end: NSSlider) {
        enable.state = m.enabled ? .on : .off
        start.doubleValue = m.start
        end.doubleValue = m.end
    }

    private func refreshLabels() {
        angleLabel.stringValue = "Angle (direction): \(fmt(angleSlider.doubleValue))°"
        centerLabel.stringValue = "Split / center: \(fmt(centerSlider.doubleValue))"
        brightLabel.stringValue = "Bright opacity (dim): \(fmt(brightSlider.doubleValue))"
        dimLabel.stringValue = "Dim opacity (strength): \(fmt(dimSlider.doubleValue))"
        let modeTag = ShadeSettingsStore.shared.settings.transitionMode.displayName.lowercased()
        widthLabel.stringValue = "Transition width (\(modeTag)): \(fmt(widthSlider.doubleValue))"
        contrastStartLabel.stringValue = "  Start (bright side): \(fmt(contrastStart.doubleValue))"
        contrastEndLabel.stringValue = "  End (dim side): \(fmt(contrastEnd.doubleValue))"
        satStartLabel.stringValue = "  Start (bright side): \(fmt(satStart.doubleValue))"
        satEndLabel.stringValue = "  End (dim side): \(fmt(satEnd.doubleValue))"
        sharpStartLabel.stringValue = "  Start (bright side): \(fmt(sharpStart.doubleValue))"
        sharpEndLabel.stringValue = "  End (dim side): \(fmt(sharpEnd.doubleValue))"
        warmStartLabel.stringValue = "  Start (bright side): \(fmt(warmStart.doubleValue))"
        warmEndLabel.stringValue = "  End (dim side): \(fmt(warmEnd.doubleValue))"
    }

    private func pushFromUI() {
        guard !updating else { return }
        ShadeSettingsStore.shared.update { s in
            s.enabled = enabledButton.state == .on
            s.inverted = invertedButton.state == .on
            s.angleDegrees = angleSlider.doubleValue
            s.center = centerSlider.doubleValue
            s.brightOpacity = brightSlider.doubleValue
            s.dimOpacity = dimSlider.doubleValue
            s.contrast.start = contrastStart.doubleValue
            s.contrast.end = contrastEnd.doubleValue
            s.saturation.start = satStart.doubleValue
            s.saturation.end = satEnd.doubleValue
            s.sharpness.start = sharpStart.doubleValue
            s.sharpness.end = sharpEnd.doubleValue
            s.warmth.start = warmStart.doubleValue
            s.warmth.end = warmEnd.doubleValue
        }
        refreshLabels()
    }

    @objc private func toggleEnabled() { pushFromUI() }
    @objc private func toggleInverted() { pushFromUI() }
    @objc private func sliderChanged(_ sender: Any?) { pushFromUI() }

    @objc private func metricToggled(_ sender: NSButton) {
        guard !updating else { return }
        let wantOn = sender.state == .on
        if wantOn {
            let ok = overlay?.requestCapturePermission() ?? CGRequestScreenCaptureAccess()
            if !ok {
                sender.state = .off
                permissionLabel.stringValue = "Screen Recording denied — contrast/sat/sharp/warmth unavailable. Dim still works."
                return
            }
        }
        ShadeSettingsStore.shared.update { s in
            switch sender.tag {
            case 1: s.contrast.enabled = wantOn
            case 2: s.saturation.enabled = wantOn
            case 3: s.sharpness.enabled = wantOn
            case 4: s.warmth.enabled = wantOn
            default: break
            }
        }
        pushFromUI()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard !updating else { return }
        let idx = sender.selectedSegment
        guard idx >= 0, idx < modeOrder.count else { return }
        ShadeSettingsStore.shared.update { $0.applyTransitionMode(modeOrder[idx]) }
        updating = true
        widthSlider.doubleValue = ShadeSettingsStore.shared.settings.effectiveTransitionWidth
        modeHintLabel.stringValue = modeHint(for: modeOrder[idx])
        updating = false
        refreshLabels()
    }

    @objc private func widthChanged(_ sender: Any?) {
        guard !updating else { return }
        ShadeSettingsStore.shared.update { $0.applyTransitionWidth(widthSlider.doubleValue) }
        updating = true
        if let idx = modeOrder.firstIndex(of: ShadeSettingsStore.shared.settings.transitionMode) {
            modeControl.selectedSegment = idx
        }
        modeHintLabel.stringValue = modeHint(for: ShadeSettingsStore.shared.settings.transitionMode)
        widthSlider.doubleValue = ShadeSettingsStore.shared.settings.effectiveTransitionWidth
        updating = false
        refreshLabels()
    }

    @objc private func presetLeftBright() {
        ShadeSettingsStore.shared.update { s in
            s.angleDegrees = 0
            s.inverted = false
            s.center = 0.5
            s.brightOpacity = 0
            s.dimOpacity = 0.55
            s.applyTransitionMode(.short)
            s.enabled = true
        }
        syncFromStore()
    }

    @objc private func presetRightBright() {
        ShadeSettingsStore.shared.update { s in
            s.angleDegrees = 180
            s.inverted = false
            s.center = 0.5
            s.brightOpacity = 0
            s.dimOpacity = 0.55
            s.applyTransitionMode(.short)
            s.enabled = true
        }
        syncFromStore()
    }

    @objc private func presetDemoMetrics() {
        let ok = overlay?.requestCapturePermission() ?? CGRequestScreenCaptureAccess()
        ShadeSettingsStore.shared.update { s in
            s.angleDegrees = 0
            s.center = 0.5
            s.brightOpacity = 0
            s.dimOpacity = 0.15
            s.applyTransitionMode(.short)
            s.enabled = true
            if ok {
                s.contrast = MetricChannel(enabled: true, start: 0.0, end: 0.55)
                s.saturation = MetricChannel(enabled: true, start: 0.15, end: -0.55)
                s.sharpness = MetricChannel(enabled: true, start: 0.35, end: -0.35)
                s.warmth = MetricChannel(enabled: true, start: -0.1, end: 0.35)
            }
        }
        syncFromStore()
    }
}

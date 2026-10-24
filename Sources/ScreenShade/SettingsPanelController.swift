import AppKit

/// Small floating panel for live shade controls.
final class SettingsPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
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
    private var updating = false

    private let modeOrder: [TransitionMode] = [.hard, .short, .long, .custom]

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

    // MARK: - UI

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "ScreenShade"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 440))
        panel.contentView = content

        var y: CGFloat = 400

        enabledButton = checkbox("Enable overlay", action: #selector(toggleEnabled), y: &y, in: content)
        invertedButton = checkbox("Invert bright / dim sides", action: #selector(toggleInverted), y: &y, in: content)

        y -= 6
        (angleSlider, angleLabel) = labeledSlider(
            title: "Angle (direction)",
            min: 0, max: 360, value: 0,
            action: #selector(sliderChanged(_:)),
            y: &y, in: content
        )
        (centerSlider, centerLabel) = labeledSlider(
            title: "Split / center",
            min: 0, max: 1, value: 0.5,
            action: #selector(sliderChanged(_:)),
            y: &y, in: content
        )
        (brightSlider, brightLabel) = labeledSlider(
            title: "Bright opacity",
            min: 0, max: 0.95, value: 0,
            action: #selector(sliderChanged(_:)),
            y: &y, in: content
        )
        (dimSlider, dimLabel) = labeledSlider(
            title: "Dim opacity (strength)",
            min: 0, max: 0.95, value: 0.55,
            action: #selector(sliderChanged(_:)),
            y: &y, in: content
        )

        // Transition mode section
        let modeTitle = NSTextField(labelWithString: "Transition / falloff")
        modeTitle.font = .boldSystemFont(ofSize: 12)
        modeTitle.frame = NSRect(x: 16, y: y, width: 340, height: 18)
        content.addSubview(modeTitle)
        y -= 26

        modeControl = NSSegmentedControl(
            labels: modeOrder.map(\.displayName),
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged(_:))
        )
        modeControl.segmentStyle = .rounded
        modeControl.frame = NSRect(x: 16, y: y, width: 348, height: 24)
        for i in 0..<modeOrder.count {
            modeControl.setWidth(87, forSegment: i)
        }
        content.addSubview(modeControl)
        y -= 22

        modeHintLabel = NSTextField(labelWithString: modeHint(for: .short))
        modeHintLabel.font = .systemFont(ofSize: 10)
        modeHintLabel.textColor = .secondaryLabelColor
        modeHintLabel.frame = NSRect(x: 16, y: y, width: 348, height: 16)
        content.addSubview(modeHintLabel)
        y -= 24

        (widthSlider, widthLabel) = labeledSlider(
            title: "Transition width",
            min: 0, max: 1, value: TransitionMode.short.presetWidth,
            action: #selector(widthChanged(_:)),
            y: &y, in: content
        )

        let presets = NSStackView()
        presets.orientation = .horizontal
        presets.spacing = 8
        presets.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(presets)

        let leftBright = NSButton(title: "Left bright", target: self, action: #selector(presetLeftBright))
        leftBright.bezelStyle = .rounded
        let rightBright = NSButton(title: "Right bright", target: self, action: #selector(presetRightBright))
        rightBright.bezelStyle = .rounded
        let topBright = NSButton(title: "Top bright", target: self, action: #selector(presetTopBright))
        topBright.bezelStyle = .rounded
        presets.addArrangedSubview(leftBright)
        presets.addArrangedSubview(rightBright)
        presets.addArrangedSubview(topBright)

        NSLayoutConstraint.activate([
            presets.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            presets.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            presets.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])

        let hint = NSTextField(labelWithString: "Config: ~/Library/Application Support/ScreenShade/config.json")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hint.bottomAnchor.constraint(equalTo: presets.topAnchor, constant: -10)
        ])

        return panel
    }

    private func modeHint(for mode: TransitionMode) -> String {
        switch mode {
        case .hard:
            return "Hard: sharp cutoff at the split (step edge)."
        case .short:
            return "Short: narrow soft ramp between bright and dim."
        case .long:
            return "Long: wide soft ramp across much of the screen."
        case .custom:
            return "Custom: dial transition width freely between hard and long."
        }
    }

    private func checkbox(_ title: String, action: Selector, y: inout CGFloat, in parent: NSView) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.frame = NSRect(x: 16, y: y, width: 340, height: 22)
        parent.addSubview(button)
        y -= 28
        return button
    }

    private func labeledSlider(
        title: String,
        min: Double,
        max: Double,
        value: Double,
        action: Selector,
        y: inout CGFloat,
        in parent: NSView
    ) -> (NSSlider, NSTextField) {
        let label = NSTextField(labelWithString: "\(title): \(format(value))")
        label.frame = NSRect(x: 16, y: y, width: 340, height: 18)
        label.font = .systemFont(ofSize: 12)
        parent.addSubview(label)
        y -= 22

        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.frame = NSRect(x: 16, y: y, width: 348, height: 22)
        slider.isContinuous = true
        parent.addSubview(slider)
        y -= 30
        return (slider, label)
    }

    private func format(_ value: Double) -> String {
        if value >= 10 || (value == floor(value) && value >= 1) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

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
        refreshLabels()
    }

    private func refreshLabels() {
        let s = ShadeSettingsStore.shared.settings
        angleLabel.stringValue = "Angle (direction): \(format(angleSlider.doubleValue))°"
        centerLabel.stringValue = "Split / center: \(format(centerSlider.doubleValue))"
        brightLabel.stringValue = "Bright opacity: \(format(brightSlider.doubleValue))"
        dimLabel.stringValue = "Dim opacity (strength): \(format(dimSlider.doubleValue))"
        let modeTag = s.transitionMode.displayName.lowercased()
        widthLabel.stringValue = "Transition width (\(modeTag)): \(format(widthSlider.doubleValue))"
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
        }
        refreshLabels()
    }

    @objc private func toggleEnabled() { pushFromUI() }
    @objc private func toggleInverted() { pushFromUI() }
    @objc private func sliderChanged(_ sender: Any?) { pushFromUI() }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard !updating else { return }
        let idx = sender.selectedSegment
        guard idx >= 0, idx < modeOrder.count else { return }
        let mode = modeOrder[idx]
        ShadeSettingsStore.shared.update { s in
            s.applyTransitionMode(mode)
        }
        updating = true
        widthSlider.doubleValue = ShadeSettingsStore.shared.settings.effectiveTransitionWidth
        modeHintLabel.stringValue = modeHint(for: mode)
        updating = false
        refreshLabels()
    }

    @objc private func widthChanged(_ sender: Any?) {
        guard !updating else { return }
        ShadeSettingsStore.shared.update { s in
            s.applyTransitionWidth(widthSlider.doubleValue)
        }
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
            s.dimOpacity = 0.6
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
            s.dimOpacity = 0.6
            s.applyTransitionMode(.short)
            s.enabled = true
        }
        syncFromStore()
    }

    @objc private func presetTopBright() {
        ShadeSettingsStore.shared.update { s in
            s.angleDegrees = 90
            s.inverted = false
            s.center = 0.5
            s.brightOpacity = 0
            s.dimOpacity = 0.55
            s.applyTransitionMode(.long)
            s.enabled = true
        }
        syncFromStore()
    }
}

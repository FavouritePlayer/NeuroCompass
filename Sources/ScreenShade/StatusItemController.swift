import AppKit

final class StatusItemController {
    private let statusItem: NSStatusItem
    private let settingsPanel: SettingsPanelController
    private weak var overlay: OverlayController?

    init(overlay: OverlayController, settingsPanel: SettingsPanelController) {
        self.overlay = overlay
        self.settingsPanel = settingsPanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "ScreenShade")
            button.image?.isTemplate = true
            button.toolTip = "ScreenShade"
        }
        statusItem.menu = buildMenu()

        NotificationCenter.default.addObserver(
            forName: .shadeSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.statusItem.menu = self?.buildMenu()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let enabled = ShadeSettingsStore.shared.settings.enabled

        let toggle = NSMenuItem(
            title: enabled ? "Disable Overlay" : "Enable Overlay",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        toggle.target = self
        menu.addItem(toggle)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let left = NSMenuItem(title: "Preset: Left Bright", action: #selector(presetLeft), keyEquivalent: "1")
        left.target = self
        menu.addItem(left)

        let right = NSMenuItem(title: "Preset: Right Bright", action: #selector(presetRight), keyEquivalent: "2")
        right.target = self
        menu.addItem(right)

        let metrics = NSMenuItem(title: "Preset: Demo Metrics", action: #selector(presetMetrics), keyEquivalent: "3")
        metrics.target = self
        menu.addItem(metrics)

        menu.addItem(.separator())

        let hard = NSMenuItem(title: "Transition: Hard", action: #selector(modeHard), keyEquivalent: "")
        hard.target = self
        menu.addItem(hard)
        let short = NSMenuItem(title: "Transition: Short", action: #selector(modeShort), keyEquivalent: "")
        short.target = self
        menu.addItem(short)
        let long = NSMenuItem(title: "Transition: Long", action: #selector(modeLong), keyEquivalent: "")
        long.target = self
        menu.addItem(long)

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload config.json", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let reveal = NSMenuItem(title: "Reveal Config Folder", action: #selector(revealConfig), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ScreenShade", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleEnabled() {
        ShadeSettingsStore.shared.update { $0.enabled.toggle() }
    }

    @objc private func openSettings() {
        settingsPanel.show()
    }

    @objc private func presetLeft() {
        ShadeSettingsStore.shared.update { s in
            s.angleDegrees = 0
            s.inverted = false
            s.center = 0.5
            s.brightOpacity = 0
            s.dimOpacity = 0.6
            s.applyTransitionMode(.short)
            s.enabled = true
        }
    }

    @objc private func presetRight() {
        ShadeSettingsStore.shared.update { s in
            s.angleDegrees = 180
            s.inverted = false
            s.center = 0.5
            s.brightOpacity = 0
            s.dimOpacity = 0.6
            s.applyTransitionMode(.short)
            s.enabled = true
        }
    }

    @objc private func presetMetrics() {
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
    }

    @objc private func modeHard() {
        ShadeSettingsStore.shared.update { $0.applyTransitionMode(.hard) }
    }

    @objc private func modeShort() {
        ShadeSettingsStore.shared.update { $0.applyTransitionMode(.short) }
    }

    @objc private func modeLong() {
        ShadeSettingsStore.shared.update { $0.applyTransitionMode(.long) }
    }

    @objc private func reloadConfig() {
        ShadeSettingsStore.shared.reloadFromDisk()
    }

    @objc private func revealConfig() {
        try? FileManager.default.createDirectory(at: ShadeSettings.supportDirectory, withIntermediateDirectories: true)
        // Ensure a config file exists so Finder has something useful.
        _ = ShadeSettingsStore.shared.settings
        NSWorkspace.shared.activateFileViewerSelecting([ShadeSettings.configURL])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

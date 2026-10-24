import AppKit

/// Manages one click-through, borderless overlay window per connected display.
final class OverlayController {
    private var windows: [NSWindow] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        recreateWindows()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.recreateWindows()
        })
        observers.append(nc.addObserver(forName: .shadeSettingsDidChange, object: nil, queue: .main) { [weak self] note in
            let settings = (note.object as? ShadeSettings) ?? ShadeSettingsStore.shared.settings
            self?.apply(settings)
        })
        apply(ShadeSettingsStore.shared.settings)
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func recreateWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        for screen in NSScreen.screens {
            let window = makeOverlayWindow(for: screen)
            windows.append(window)
            window.orderFrontRegardless()
        }
        apply(ShadeSettingsStore.shared.settings)
    }

    func apply(_ settings: ShadeSettings) {
        for window in windows {
            window.setIsVisible(settings.enabled)
            if let view = window.contentView as? GradientOverlayView {
                view.apply(settings)
            }
        }
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        window.sharingType = .readOnly
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.transient)

        let view = GradientOverlayView(frame: screen.frame)
        view.apply(ShadeSettingsStore.shared.settings)
        window.contentView = view

        // Cover the exact screen frame (including menu bar area).
        window.setFrame(screen.frame, display: true)

        return window
    }
}

import AppKit

/// Manages one click-through overlay window per display, with optional capture+filter path.
final class OverlayController {
    private struct DisplayOverlay {
        let window: NSWindow
        let view: OverlayContentView
        let displayID: CGDirectDisplayID
        let capture: ScreenCaptureEngine
    }

    private var overlays: [DisplayOverlay] = []
    private var observers: [NSObjectProtocol] = []
    private var settings = ShadeSettingsStore.shared.settings
    private(set) var capturePermissionGranted = CGPreflightScreenCaptureAccess()

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
        // Capture engines stop when released; avoid calling @MainActor stop() from deinit.
    }

    func recreateWindows() {
        overlays.forEach {
            $0.capture.stop()
            $0.window.orderOut(nil)
        }
        overlays.removeAll()

        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            let window = makeOverlayWindow(for: screen)
            guard let view = window.contentView as? OverlayContentView else { continue }
            let engine = ScreenCaptureEngine()
            engine.onPermissionChange = { [weak self] granted in
                self?.capturePermissionGranted = granted
                NotificationCenter.default.post(name: .shadeCapturePermissionDidChange, object: granted)
                if !granted {
                    // Fall back to dim-only if permission denied.
                    ShadeSettingsStore.shared.update { s in
                        s.contrast.enabled = false
                        s.saturation.enabled = false
                        s.sharpness.enabled = false
                        s.warmth.enabled = false
                    }
                }
            }
            engine.onFrame = { [weak view] cgImage in
                guard let view, let processed = MetricProcessor.process(cgImage: cgImage, settings: ShadeSettingsStore.shared.settings) else { return }
                view.showFilteredFrame(processed)
            }
            overlays.append(DisplayOverlay(window: window, view: view, displayID: displayID, capture: engine))
            window.orderFrontRegardless()
        }
        apply(ShadeSettingsStore.shared.settings)
    }

    func apply(_ settings: ShadeSettings) {
        self.settings = settings
        let excludeIDs = overlays.map { CGWindowID($0.window.windowNumber) }

        for overlay in overlays {
            overlay.window.setIsVisible(settings.enabled)
            overlay.view.apply(settings)

            if settings.enabled && settings.needsScreenCapture {
                overlay.capture.start(displayID: overlay.displayID, excludingWindowIDs: excludeIDs)
            } else {
                overlay.capture.stop()
                overlay.view.clearFilteredFrame()
            }
        }
    }

    /// Ask for Screen Recording permission before enabling advanced metrics.
    @discardableResult
    func requestCapturePermission() -> Bool {
        // Use the first overlay's engine (or a temporary one).
        if let first = overlays.first {
            let ok = first.capture.ensurePermission()
            capturePermissionGranted = ok
            return ok
        }
        let tmp = ScreenCaptureEngine()
        let ok = tmp.ensurePermission()
        capturePermissionGranted = ok
        return ok
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
            .fullScreenAuxiliary,
            .transient
        ]
        window.sharingType = .none
        window.isReleasedWhenClosed = false

        let view = OverlayContentView(frame: screen.frame)
        view.apply(ShadeSettingsStore.shared.settings)
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        return window
    }
}

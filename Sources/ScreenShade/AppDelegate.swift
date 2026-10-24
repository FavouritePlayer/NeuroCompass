import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayController!
    private var settingsPanel: SettingsPanelController!
    private var statusItemController: StatusItemController!
    private var loopWatcher: LoopCommandWatcher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ShadeSettingsStore.shared

        overlayController = OverlayController()
        settingsPanel = SettingsPanelController(overlay: overlayController)
        statusItemController = StatusItemController(
            overlay: overlayController,
            settingsPanel: settingsPanel
        )

        // NeuroCompass (and other drivers) write loop.json; apply left-contrast live.
        loopWatcher = LoopCommandWatcher()
        loopWatcher.start()

        settingsPanel.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

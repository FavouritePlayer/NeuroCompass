import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayController!
    private var settingsPanel: SettingsPanelController!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure settings are loaded / config written on first launch.
        _ = ShadeSettingsStore.shared

        overlayController = OverlayController()
        settingsPanel = SettingsPanelController()
        statusItemController = StatusItemController(
            overlay: overlayController,
            settingsPanel: settingsPanel
        )

        // Show settings once so the first-run slice is discoverable.
        settingsPanel.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

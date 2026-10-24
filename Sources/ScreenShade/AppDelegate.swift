import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayController!
    private var settingsPanel: SettingsPanelController!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ShadeSettingsStore.shared

        overlayController = OverlayController()
        settingsPanel = SettingsPanelController(overlay: overlayController)
        statusItemController = StatusItemController(
            overlay: overlayController,
            settingsPanel: settingsPanel
        )

        settingsPanel.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

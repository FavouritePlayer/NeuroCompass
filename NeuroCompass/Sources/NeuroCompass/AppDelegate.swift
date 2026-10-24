import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWC: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWC = MainWindowController()
        mainWC.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

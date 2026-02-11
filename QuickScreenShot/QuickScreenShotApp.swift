import SwiftUI

@main
struct QuickScreenShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var screenshotManager = ScreenshotManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(screenshotManager)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(screenshotManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep app in dock
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

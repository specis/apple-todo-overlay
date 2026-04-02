import SwiftUI

@main
struct apple_todo_overlayApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Tasks", systemImage: "checklist") {
            Button("Show HUD") { HUDController.shared.show() }
            Button("Hide HUD") { HUDController.shared.hide() }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try LocalDatabase.shared.open()
        } catch {
            fatalError("Failed to open database: \(error)")
        }

        HUDController.shared.setup()
        HUDController.shared.show()
    }
}

import SwiftUI

@main
struct apple_todo_overlayApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hudOpacity") private var hudOpacity: Double = 1.0

    var body: some Scene {
        MenuBarExtra("Tasks", systemImage: "checklist",
                     isInserted: Binding(
                        get: { HUDController.shared.isVisible },
                        set: { _ in }
                     )) {
            Button("Show HUD") { HUDController.shared.show() }
            Button("Hide HUD") { HUDController.shared.hide() }
            Divider()
            if HUDController.shared.accessibilityGranted {
                Label("⌃⌥Space to toggle", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    HUDController.shared.checkAndRequestAccessibility()
                } label: {
                    Label("Grant Accessibility access…", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity \(Int(hudOpacity * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $hudOpacity, in: 0.2...1.0, step: 0.05)
                    .onChange(of: hudOpacity) { _, newValue in
                        HUDController.shared.setOpacity(newValue)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            Divider()
            Button("Connect Microsoft To Do…") {
                Task {
                    let ok = await AppDelegate.msTodoProvider.signIn()
                    if ok {
                        // Reset stored sync timestamp so the next cycle fetches all tasks,
                        // not just those modified since the last (possibly failed) attempt.
                        try? SyncStateStore.updateLastSync(for: .microsoftTodo, date: .distantPast)
                        SyncManager.shared.register(AppDelegate.msTodoProvider, for: .microsoftTodo)
                        SyncManager.shared.triggerSync()
                    }
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = ok ? "Connected" : "Sign-in failed"
                        alert.informativeText = ok
                            ? "Microsoft To Do is connected. Syncing now."
                            : "Could not complete sign-in. Check the console log (make run) for details."
                        alert.alertStyle = ok ? .informational : .warning
                        alert.runModal()
                    }
                }
            }
            Button("Sync Now") {
                SyncManager.shared.triggerSync()
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    static let msTodoProvider = MicrosoftTodoProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try LocalDatabase.shared.open()
        } catch {
            fatalError("Failed to open database: \(error)")
        }

        HUDController.shared.setup()
        HUDController.shared.show()

        Task { await setupSync() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SyncManager.shared.stop()
    }

    private func setupSync() async {
        // Apple Reminders
        let reminders = AppleRemindersProvider()
        if !reminders.isAvailable() {
            _ = await reminders.requestAccess()
        }
        if reminders.isAvailable() {
            SyncManager.shared.register(reminders, for: .appleReminders)
        }

        // CloudKit — available whenever the user is signed in to iCloud
        let cloudKit = CloudKitProvider()
        if cloudKit.isAvailable() {
            SyncManager.shared.register(cloudKit, for: .cloudKit)
        }

        // Microsoft To Do — available after the user completes OAuth sign-in
        if Self.msTodoProvider.isAvailable() {
            SyncManager.shared.register(Self.msTodoProvider, for: .microsoftTodo)
        }

        SyncManager.shared.start()
    }
}

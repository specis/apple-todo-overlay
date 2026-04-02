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

    private let remindersProvider = AppleRemindersProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try LocalDatabase.shared.open()
        } catch {
            fatalError("Failed to open database: \(error)")
        }

        HUDController.shared.setup()
        HUDController.shared.show()

        Task { await syncReminders() }
    }

    private func syncReminders() async {
        // Request access if not already granted
        if !remindersProvider.isAvailable() {
            guard await remindersProvider.requestAccess() else { return }
        }

        let since = (try? SyncStateStore.lastSyncDate(for: .appleReminders)) ?? .distantPast

        do {
            let remote = try await remindersProvider.fetchChanges(since: since)
            let lists  = try await remindersProvider.fetchLists()

            // Persist lists
            for list in lists {
                try? LocalDatabase.shared.run("""
                    INSERT OR IGNORE INTO task_lists
                        (id, name, source, external_id, created_at, last_modified)
                    VALUES (?, ?, ?, ?, ?, ?);
                """, params: [list.id, list.name, list.source.rawValue,
                              list.externalId, list.createdAt, list.lastModified])
            }

            // Upsert remote tasks
            let repo = TaskRepository.shared
            let existing = try repo.getAllTasks()
            let existingByExternalId = Dictionary(
                uniqueKeysWithValues: existing.compactMap { t in t.externalId.map { ($0, t) } }
            )

            for remote in remote {
                if let local = existingByExternalId[remote.externalId ?? ""] {
                    // Keep local if it was modified more recently
                    if remote.lastModified > local.lastModified {
                        var updated = remote
                        updated = TodoTask(
                            id: local.id, title: remote.title, notes: remote.notes,
                            dueDate: remote.dueDate, completed: remote.completed,
                            completedAt: remote.completedAt, source: remote.source,
                            externalId: remote.externalId, createdAt: local.createdAt,
                            lastModified: remote.lastModified, syncStatus: .synced,
                            listId: remote.listId, priority: remote.priority, tags: local.tags
                        )
                        try repo.updateTask(updated)
                    }
                } else {
                    try repo.saveTask(remote)
                }
            }

            // Push any local pending changes back to Reminders
            let pending = existing.filter { $0.syncStatus == .pendingUpload && $0.source == .appleReminders }
            try await remindersProvider.pushChanges(pending)

            try SyncStateStore.updateLastSync(for: .appleReminders, date: Date())

            // Reload the HUD
            await HUDController.shared.reload()
        } catch {
            try? SyncStateStore.updateLastSync(for: .appleReminders, date: Date(),
                                               status: "error", error: error.localizedDescription)
        }
    }
}

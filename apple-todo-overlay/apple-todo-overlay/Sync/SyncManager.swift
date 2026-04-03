import Foundation

final class SyncManager {
    static let shared = SyncManager()

    private struct Entry {
        let provider: TaskProvider
        let source: TaskSource
    }

    private var entries: [Entry] = []
    private var activeSyncTask: Task<Void, Never>?

    private init() {}

    // MARK: - Registration

    func register(_ provider: TaskProvider, for source: TaskSource) {
        entries.removeAll { $0.source == source }
        entries.append(Entry(provider: provider, source: source))
    }

    // MARK: - Lifecycle

    /// Starts the network monitor and background scheduler, then triggers an initial sync.
    func start() {
        NetworkMonitor.shared.onConnected = { [weak self] in
            self?.triggerSync()
        }
        NetworkMonitor.shared.start()

        BackgroundScheduler.shared.start {
            await SyncManager.shared.syncAll()
        }

        triggerSync()
    }

    func stop() {
        BackgroundScheduler.shared.stop()
        NetworkMonitor.shared.stop()
        activeSyncTask?.cancel()
        activeSyncTask = nil
    }

    // MARK: - Sync

    /// Triggers a background sync if one is not already running.
    func triggerSync() {
        guard activeSyncTask == nil else { return }
        activeSyncTask = Task { [weak self] in
            await self?.syncAll()
            self?.activeSyncTask = nil
        }
    }

    /// Runs a sync cycle for every registered and available provider, then reloads the HUD.
    func syncAll() async {
        for entry in entries where entry.provider.isAvailable() {
            do {
                try await SyncEngine.shared.sync(provider: entry.provider, source: entry.source)
            } catch {
                try? SyncStateStore.updateLastSync(
                    for: entry.source,
                    date: Date(),
                    status: "error",
                    error: error.localizedDescription
                )
            }
        }

        await HUDController.shared.reload()
    }
}

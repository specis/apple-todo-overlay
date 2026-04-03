import Foundation

struct SyncResult {
    let source: TaskSource
    let fetched: Int
    let pushed: Int
    let conflicts: Int
}

final class SyncEngine {
    static let shared = SyncEngine()
    private init() {}

    /// Runs a full sync cycle for one provider:
    ///   1. Fetch remote changes since the last recorded sync date.
    ///   2. Merge into the local DB using last-write-wins conflict resolution.
    ///   3. Push any locally-modified tasks back to the provider.
    ///   4. Record the new sync timestamp.
    @discardableResult
    func sync(provider: TaskProvider, source: TaskSource) async throws -> SyncResult {
        let repo = TaskRepository.shared
        let since = (try? SyncStateStore.lastSyncDate(for: source)) ?? .distantPast

        // 1. Fetch remote
        let remoteChanges = try await provider.fetchChanges(since: since)

        // 2. Build local index by externalId for fast lookup
        let localTasks = try repo.getAllTasks()
        let byExternalId: [String: TodoTask] = Dictionary(
            uniqueKeysWithValues: localTasks.compactMap { t in t.externalId.map { ($0, t) } }
        )

        var fetched = 0
        var conflicts = 0

        for remote in remoteChanges {
            fetched += 1

            guard let extId = remote.externalId else {
                // Remote task has no externalId — treat as new
                if byExternalId[remote.id] == nil {
                    try repo.saveTask(remote)
                }
                continue
            }

            if let local = byExternalId[extId] {
                let winner = ConflictResolver.resolve(local: local, remote: remote)
                if winner.lastModified > local.lastModified {
                    // Remote won the conflict — update local DB
                    try repo.updateTask(winner)
                    conflicts += 1
                }
                // Local won — no action; local change will be pushed below
            } else {
                // New remote task not yet in local DB
                try repo.saveTask(remote)
            }
        }

        // 3. Push local pending changes for this source
        let pending = localTasks.filter {
            $0.syncStatus == .pendingUpload && $0.source == source
        }
        if !pending.isEmpty {
            try await provider.pushChanges(pending)
            for task in pending {
                let synced = TodoTask(
                    id:           task.id,
                    title:        task.title,
                    notes:        task.notes,
                    dueDate:      task.dueDate,
                    completed:    task.completed,
                    completedAt:  task.completedAt,
                    source:       task.source,
                    externalId:   task.externalId,
                    createdAt:    task.createdAt,
                    lastModified: task.lastModified,
                    syncStatus:   .synced,
                    listId:       task.listId,
                    priority:     task.priority,
                    tags:         task.tags
                )
                try repo.updateTask(synced)
            }
        }

        // 4. Record sync timestamp
        try SyncStateStore.updateLastSync(for: source, date: Date())

        return SyncResult(source: source, fetched: fetched, pushed: pending.count, conflicts: conflicts)
    }
}

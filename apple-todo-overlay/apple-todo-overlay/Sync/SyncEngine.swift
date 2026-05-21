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
        let db   = LocalDatabase.shared
        let since = (try? SyncStateStore.lastSyncDate(for: source)) ?? .distantPast

        // 1a. Sync lists so task list_id foreign keys resolve (one transaction)
        let lists = try await provider.fetchLists()
        if !lists.isEmpty {
            try db.beginTransaction()
            do {
                for list in lists { try repo.upsertList(list) }
                try db.commitTransaction()
            } catch {
                db.rollbackTransaction()
                throw error
            }
        }

        // 1b. Fetch remote task changes
        let remoteChanges = try await provider.fetchChanges(since: since)

        // 2. Merge remote changes into local DB — one transaction for the whole batch
        let localTasks = try repo.getAllTasks()
        let byExternalId: [String: TodoTask] = Dictionary(
            uniqueKeysWithValues: localTasks.compactMap { t in t.externalId.map { ($0, t) } }
        )

        var fetched = 0
        var conflicts = 0

        if !remoteChanges.isEmpty {
            try db.beginTransaction()
            do {
                for remote in remoteChanges {
                    fetched += 1

                    guard let extId = remote.externalId else {
                        if byExternalId[remote.id] == nil { try repo.saveTask(remote) }
                        continue
                    }

                    if let local = byExternalId[extId] {
                        let winner = ConflictResolver.resolve(local: local, remote: remote)
                        if winner.lastModified > local.lastModified {
                            try repo.updateTask(winner)
                            conflicts += 1
                        }
                    } else {
                        try repo.saveTask(remote)
                    }
                }
                try db.commitTransaction()
            } catch {
                db.rollbackTransaction()
                throw error
            }
        }

        // 3. Push local pending changes then mark them synced in one transaction
        let pending = localTasks.filter {
            $0.syncStatus == .pendingUpload && ($0.source == source || $0.source == .local)
        }
        if !pending.isEmpty {
            try await provider.pushChanges(pending)
            // Mark synced without reconstructing stale snapshots — pushChanges may have
            // written externalId/source for newly-created tasks and we must not clobber them.
            try db.beginTransaction()
            do {
                try repo.markSynced(ids: pending.map(\.id))
                try db.commitTransaction()
            } catch {
                db.rollbackTransaction()
                throw error
            }
        }

        // 4. Push deletions — remote-delete then hard-purge locally in one transaction
        let deleted = (try? repo.getDeletedTasks(for: source)) ?? []
        if !deleted.isEmpty {
            try await provider.deleteRemote(deleted)
            try db.beginTransaction()
            do {
                for task in deleted { try repo.hardDeleteTask(id: task.id) }
                try db.commitTransaction()
            } catch {
                db.rollbackTransaction()
                throw error
            }
        }

        // 5. Record sync timestamp
        try SyncStateStore.updateLastSync(for: source, date: Date())

        return SyncResult(source: source, fetched: fetched, pushed: pending.count, conflicts: conflicts)
    }
}

import Foundation

enum ConflictResolver {

    /// Last-write-wins: returns the task whose `lastModified` is newer.
    /// On a tie the local version is preferred (optimistic local-first).
    /// The winning task always keeps the local `id` and `tags` so that
    /// local relationships (tag assignments) are never overwritten by a
    /// remote source that doesn't carry tag data (e.g. Apple Reminders).
    static func resolve(local: TodoTask, remote: TodoTask) -> TodoTask {
        guard remote.lastModified > local.lastModified else {
            return local  // local wins or tie — no change
        }

        // Remote wins — adopt remote content but keep local identity and tags
        return TodoTask(
            id:           local.id,
            title:        remote.title,
            notes:        remote.notes,
            dueDate:      remote.dueDate,
            completed:    remote.completed,
            completedAt:  remote.completedAt,
            source:       remote.source,
            externalId:   remote.externalId,
            createdAt:    local.createdAt,
            lastModified: remote.lastModified,
            syncStatus:   .synced,
            listId:       remote.listId,
            priority:     remote.priority,
            tags:         local.tags
        )
    }
}

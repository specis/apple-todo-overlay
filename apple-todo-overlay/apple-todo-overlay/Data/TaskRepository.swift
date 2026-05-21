import Foundation

final class TaskRepository {

    static let shared = TaskRepository()
    private let db = LocalDatabase.shared

    private init() {}

    // MARK: - Read

    func getAllTasks() throws -> [TodoTask] {
        let rows = try db.query("""
            SELECT * FROM tasks
            WHERE is_deleted = 0
            ORDER BY (due_date IS NULL), due_date ASC, created_at DESC;
        """)
        guard !rows.isEmpty else { return [] }

        // Fetch all tags for active tasks in one JOIN — avoids N+1 per-task queries.
        let tagRows = try db.query("""
            SELECT tt.task_id, t.id, t.name, t.colour, t.created_at
            FROM task_tags tt
            JOIN tags t ON t.id = tt.tag_id
            WHERE tt.task_id IN (SELECT id FROM tasks WHERE is_deleted = 0);
        """)
        var tagsByTask: [String: [Tag]] = [:]
        for tagRow in tagRows {
            guard let taskId = tagRow["task_id"]?.textValue,
                  let tag    = TaskMapper.toTag(row: tagRow) else { continue }
            tagsByTask[taskId, default: []].append(tag)
        }

        return rows.compactMap { row in
            guard let id = row["id"]?.textValue else { return nil }
            return TaskMapper.toTask(row: row, tags: tagsByTask[id] ?? [])
        }
    }

    func getAllLists() throws -> [TaskList] {
        let rows = try db.query("""
            SELECT * FROM task_lists WHERE is_deleted = 0 ORDER BY name ASC;
        """)
        return rows.compactMap { TaskMapper.toTaskList(row: $0) }
    }

    /// Returns soft-deleted tasks for a given source that still have a remote externalId
    /// and therefore need to be deleted on the remote provider.
    func getDeletedTasks(for source: TaskSource) throws -> [TodoTask] {
        let rows = try db.query("""
            SELECT * FROM tasks
            WHERE is_deleted = 1 AND source = ? AND external_id IS NOT NULL;
        """, params: [source.rawValue])
        return rows.compactMap { row in
            guard let id = row["id"]?.textValue else { return nil }
            return TaskMapper.toTask(row: row, tags: [])
        }
    }

    func hardDeleteTask(id: String) throws {
        try db.run("DELETE FROM tasks WHERE id = ?;", params: [id])
    }

    // MARK: - Write

    func saveTask(_ task: TodoTask) throws {
        try db.run("""
            INSERT INTO tasks
                (id, list_id, title, notes, due_date, completed, completed_at,
                 source, external_id, created_at, last_modified, sync_status, priority)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, params: [
            task.id,
            task.listId,
            task.title,
            task.notes,
            task.dueDate,
            task.completed,
            task.completedAt,
            task.source.rawValue,
            task.externalId,
            task.createdAt,
            task.lastModified,
            task.syncStatus.rawValue,
            task.priority.rawValue
        ])

        for tag in task.tags {
            try addTag(tagId: tag.id, toTask: task.id)
        }
    }

    func updateTask(_ task: TodoTask) throws {
        try db.run("""
            UPDATE tasks SET
                list_id = ?, title = ?, notes = ?, due_date = ?,
                completed = ?, completed_at = ?, source = ?, external_id = ?,
                last_modified = ?, sync_status = ?, priority = ?
            WHERE id = ?;
        """, params: [
            task.listId,
            task.title,
            task.notes,
            task.dueDate,
            task.completed,
            task.completedAt,
            task.source.rawValue,
            task.externalId,
            task.lastModified,
            task.syncStatus.rawValue,
            task.priority.rawValue,
            task.id
        ])
    }

    /// Marks a batch of tasks as synced without touching any other field.
    /// Used after a push to avoid clobbering externalId/source written during the push.
    func markSynced(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        try db.run(
            "UPDATE tasks SET sync_status = 'SYNCED' WHERE id IN (\(placeholders));",
            params: ids.map { $0 as Any? }
        )
    }

    func markCompleted(id: String, completed: Bool) throws {
        let now = Date()
        try db.run("""
            UPDATE tasks
            SET completed = ?, completed_at = ?, last_modified = ?, sync_status = 'PENDING_UPLOAD'
            WHERE id = ?;
        """, params: [completed, completed ? now : nil, now, id])
    }

    func deleteTask(id: String) throws {
        try db.run("""
            UPDATE tasks
            SET is_deleted = 1, last_modified = ?, sync_status = 'PENDING_UPLOAD'
            WHERE id = ?;
        """, params: [Date(), id])
    }

    // MARK: - Lists

    func upsertList(_ list: TaskList) throws {
        try db.run("""
            INSERT INTO task_lists (id, name, source, external_id, created_at, last_modified)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name          = excluded.name,
                last_modified = excluded.last_modified;
        """, params: [
            list.id,
            list.name,
            list.source.rawValue,
            list.externalId,
            list.createdAt,
            list.lastModified
        ])
    }

    // MARK: - Tag associations

    private func fetchTags(forTaskId taskId: String) throws -> [Tag] {
        let rows = try db.query("""
            SELECT t.* FROM tags t
            JOIN task_tags tt ON tt.tag_id = t.id
            WHERE tt.task_id = ?;
        """, params: [taskId])
        return rows.compactMap { TaskMapper.toTag(row: $0) }
    }

    func addTag(tagId: String, toTask taskId: String) throws {
        try db.run("""
            INSERT OR IGNORE INTO task_tags (task_id, tag_id) VALUES (?, ?);
        """, params: [taskId, tagId])
    }

    func removeTag(tagId: String, fromTask taskId: String) throws {
        try db.run("""
            DELETE FROM task_tags WHERE task_id = ? AND tag_id = ?;
        """, params: [taskId, tagId])
    }

    func removeAllTags(forTaskId taskId: String) throws {
        try db.run("DELETE FROM task_tags WHERE task_id = ?;", params: [taskId])
    }
}

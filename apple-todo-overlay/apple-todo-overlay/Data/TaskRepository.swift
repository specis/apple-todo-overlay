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
        return try rows.compactMap { row in
            guard let id = row["id"]?.textValue else { return nil }
            let tags = try fetchTags(forTaskId: id)
            return TaskMapper.toTask(row: row, tags: tags)
        }
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
                completed = ?, completed_at = ?, last_modified = ?,
                sync_status = ?, priority = ?
            WHERE id = ?;
        """, params: [
            task.listId,
            task.title,
            task.notes,
            task.dueDate,
            task.completed,
            task.completedAt,
            task.lastModified,
            task.syncStatus.rawValue,
            task.priority.rawValue,
            task.id
        ])
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

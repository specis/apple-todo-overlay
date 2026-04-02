import Foundation

enum TaskMapper {

    static func toTask(row: Row, tags: [Tag] = []) -> TodoTask? {
        guard
            let id           = row["id"]?.textValue,
            let title        = row["title"]?.textValue,
            let sourceStr    = row["source"]?.textValue,
            let source       = TaskSource(rawValue: sourceStr),
            let createdAt    = row["created_at"]?.dateValue,
            let lastModified = row["last_modified"]?.dateValue,
            let syncStr      = row["sync_status"]?.textValue,
            let syncStatus   = SyncStatus(rawValue: syncStr),
            let priorityStr  = row["priority"]?.textValue,
            let priority     = Priority(rawValue: priorityStr)
        else { return nil }

        return TodoTask(
            id:           id,
            title:        title,
            notes:        row["notes"]?.textValue,
            dueDate:      row["due_date"]?.dateValue,
            completed:    row["completed"]?.boolValue ?? false,
            completedAt:  row["completed_at"]?.dateValue,
            source:       source,
            externalId:   row["external_id"]?.textValue,
            createdAt:    createdAt,
            lastModified: lastModified,
            syncStatus:   syncStatus,
            listId:       row["list_id"]?.textValue,
            priority:     priority,
            tags:         tags
        )
    }

    static func toTag(row: Row) -> Tag? {
        guard
            let id        = row["id"]?.textValue,
            let name      = row["name"]?.textValue,
            let colour    = row["colour"]?.textValue,
            let createdAt = row["created_at"]?.dateValue
        else { return nil }

        return Tag(id: id, name: name, colour: colour, createdAt: createdAt)
    }

    static func toTaskList(row: Row) -> TaskList? {
        guard
            let id           = row["id"]?.textValue,
            let name         = row["name"]?.textValue,
            let sourceStr    = row["source"]?.textValue,
            let source       = TaskSource(rawValue: sourceStr),
            let createdAt    = row["created_at"]?.dateValue,
            let lastModified = row["last_modified"]?.dateValue
        else { return nil }

        return TaskList(
            id:           id,
            name:         name,
            source:       source,
            externalId:   row["external_id"]?.textValue,
            createdAt:    createdAt,
            lastModified: lastModified
        )
    }
}

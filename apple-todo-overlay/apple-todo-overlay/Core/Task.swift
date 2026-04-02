import Foundation

struct TodoTask: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var completed: Bool
    var completedAt: Date?
    var source: TaskSource
    var externalId: String?
    let createdAt: Date
    var lastModified: Date
    var syncStatus: SyncStatus
    var listId: String?
    var priority: Priority
    var tags: [Tag]
}

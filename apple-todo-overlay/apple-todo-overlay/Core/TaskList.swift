import Foundation

struct TaskList: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var source: TaskSource
    var externalId: String?
    let createdAt: Date
    var lastModified: Date
}

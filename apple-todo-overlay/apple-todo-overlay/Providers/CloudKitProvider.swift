import Foundation

// Placeholder — will be implemented in task #8
final class CloudKitProvider: TaskProvider {
    func fetchChanges(since date: Date) async throws -> [TodoTask] { [] }
    func pushChanges(_ tasks: [TodoTask]) async throws {}
    func fetchLists() async throws -> [TaskList] { [] }
    func isAvailable() -> Bool { false }
}

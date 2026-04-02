import Foundation

// Placeholder — will be implemented in task #6
final class AppleRemindersProvider: TaskProvider {
    func fetchChanges(since date: Date) async throws -> [TodoTask] { [] }
    func pushChanges(_ tasks: [TodoTask]) async throws {}
    func fetchLists() async throws -> [TaskList] { [] }
    func isAvailable() -> Bool { false }
}

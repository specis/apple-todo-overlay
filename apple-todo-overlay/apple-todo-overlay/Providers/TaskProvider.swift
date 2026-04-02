import Foundation

protocol TaskProvider {
    func fetchChanges(since date: Date) async throws -> [TodoTask]
    func pushChanges(_ tasks: [TodoTask]) async throws
    func fetchLists() async throws -> [TaskList]
    func isAvailable() -> Bool
}

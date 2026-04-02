import Foundation

@Observable
final class TaskViewModel {

    var activeFilter: SmartList = .dueToday
    private(set) var tasks: [TodoTask] = []
    private(set) var errorMessage: String?

    init() {
        load()
    }

    var filteredTasks: [TodoTask] {
        FilterService.apply(activeFilter, to: tasks)
    }

    // MARK: - Load

    func load() {
        do {
            tasks = try TaskRepository.shared.getAllTasks()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    func toggleComplete(_ task: TodoTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        // Optimistic update — apply immediately so the UI feels instant
        let newCompleted = !task.completed
        tasks[i].completed = newCompleted
        tasks[i].completedAt = newCompleted ? Date() : nil
        tasks[i].lastModified = Date()
        tasks[i].syncStatus = .pendingUpload

        do {
            try TaskRepository.shared.markCompleted(id: task.id, completed: newCompleted)
        } catch {
            // Roll back on failure
            tasks[i] = task
            errorMessage = error.localizedDescription
        }
    }
}

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

    func createTask(from parsed: ParsedInput) {
        guard !parsed.title.isEmpty else { return }
        let now = Date()
        let task = TodoTask(
            id: UUID().uuidString,
            title: parsed.title,
            notes: nil,
            dueDate: parsed.dueDate,
            completed: false,
            completedAt: nil,
            source: .local,
            externalId: nil,
            createdAt: now,
            lastModified: now,
            syncStatus: .pendingUpload,
            listId: nil,
            priority: parsed.priority,
            tags: []
        )

        // Optimistic insert at the top
        tasks.insert(task, at: 0)

        do {
            try TaskRepository.shared.saveTask(task)
        } catch {
            tasks.removeAll { $0.id == task.id }
            errorMessage = error.localizedDescription
        }
    }

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

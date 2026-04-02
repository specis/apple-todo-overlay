import Foundation

@Observable
final class TaskViewModel {

    var activeFilter: SmartList = .dueToday
    var activeTagFilter: Tag? = nil
    var editingTaskId: String? = nil
    private(set) var tasks: [TodoTask] = []
    private(set) var errorMessage: String?

    init() {
        load()
    }

    var filteredTasks: [TodoTask] {
        let byList = FilterService.apply(activeFilter, to: tasks)
        return FilterService.applyTagFilter(activeTagFilter?.id, to: byList)
    }

    var availableTags: [Tag] {
        var seen = Set<String>()
        return tasks.flatMap { $0.tags }.filter { seen.insert($0.id).inserted }
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

    // MARK: - Create

    func createTask(from parsed: ParsedInput) {
        guard !parsed.title.isEmpty else { return }

        let resolvedTags = parsed.tagNames.compactMap { resolveOrCreateTag(named: $0) }
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
            tags: resolvedTags
        )

        tasks.insert(task, at: 0)

        do {
            try TaskRepository.shared.saveTask(task)
        } catch {
            tasks.removeAll { $0.id == task.id }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Update

    func updateTask(_ updated: TodoTask) {
        guard let i = tasks.firstIndex(where: { $0.id == updated.id }) else { return }
        tasks[i] = updated
        do {
            try TaskRepository.shared.updateTask(updated)
            try TaskRepository.shared.removeAllTags(forTaskId: updated.id)
            for tag in updated.tags {
                try TaskRepository.shared.addTag(tagId: tag.id, toTask: updated.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        editingTaskId = nil
    }

    // MARK: - Delete

    func deleteTask(_ task: TodoTask) {
        tasks.removeAll { $0.id == task.id }
        editingTaskId = nil
        do {
            try TaskRepository.shared.deleteTask(id: task.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Toggle complete

    func toggleComplete(_ task: TodoTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let newCompleted = !task.completed
        tasks[i].completed = newCompleted
        tasks[i].completedAt = newCompleted ? Date() : nil
        tasks[i].lastModified = Date()
        tasks[i].syncStatus = .pendingUpload

        do {
            try TaskRepository.shared.markCompleted(id: task.id, completed: newCompleted)
        } catch {
            tasks[i] = task
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Tag helpers

    private func resolveOrCreateTag(named name: String) -> Tag? {
        let lower = name.lowercased()
        if let existing = (try? TagRepository.shared.getAllTags())?.first(where: { $0.name.lowercased() == lower }) {
            return existing
        }
        let tag = Tag(id: UUID().uuidString, name: name,
                      colour: Tag.autoColour(for: name), createdAt: Date())
        try? TagRepository.shared.saveTag(tag)
        return tag
    }
}

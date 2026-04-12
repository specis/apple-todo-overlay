import Foundation

@Observable
final class TaskViewModel {

    var activeFilter: SmartList = .dueToday {
        didSet { updateCaches() }
    }
    var activeTagFilter: Tag? = nil {
        didSet { updateCaches() }
    }
    var editingTaskId: String? = nil
    var searchText: String = "" {
        didSet { updateCaches() }
    }
    private(set) var tasks: [TodoTask] = [] {
        didSet { updateCaches() }
    }
    private(set) var lists: [TaskList] = [] {
        didSet { updateCaches() }
    }
    private(set) var errorMessage: String?

    // Cached derived state — recomputed only when inputs change, not on every render.
    private(set) var filteredTasks: [TodoTask] = []
    private(set) var groupedFilteredTasks: [(name: String, tasks: [TodoTask])] = []
    private(set) var urgentCount: Int = 0
    private(set) var availableTags: [Tag] = []

    init() {
        load()
    }

    // MARK: - Cache update

    private func updateCaches() {
        // filteredTasks
        let filtered: [TodoTask]
        if !searchText.isEmpty {
            filtered = FilterService.applySearch(searchText, to: tasks)
        } else {
            filtered = FilterService.applyTagFilter(
                activeTagFilter?.id,
                to: FilterService.apply(activeFilter, to: tasks)
            )
        }
        filteredTasks = filtered

        // groupedFilteredTasks (only meaningful for the All view)
        let listIndex = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.name) })
        var groups: [(name: String, tasks: [TodoTask])] = []
        var seen: [String: Int] = [:]
        var local: [TodoTask] = []
        for task in filtered {
            if let listId = task.listId, let name = listIndex[listId] {
                if let i = seen[name] { groups[i].tasks.append(task) }
                else { seen[name] = groups.count; groups.append((name: name, tasks: [task])) }
            } else {
                local.append(task)
            }
        }
        if !local.isEmpty { groups.append((name: "Local", tasks: local)) }
        groupedFilteredTasks = groups.sorted { $0.name < $1.name }

        // urgentCount — one pass, reuses today/tomorrow computed once
        let cal = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        urgentCount = tasks.filter {
            guard !$0.completed, let d = $0.dueDate else { return false }
            return d < tomorrow
        }.count

        // availableTags
        var seenTags = Set<String>()
        availableTags = tasks.flatMap { $0.tags }.filter { seenTags.insert($0.id).inserted }
    }

    // MARK: - Load

    func load() {
        do {
            tasks = try TaskRepository.shared.getAllTasks()
            lists = try TaskRepository.shared.getAllLists()
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
        var saved = updated
        if updated.source != .local {
            saved.syncStatus = .pendingUpload
            saved.lastModified = Date()
        }
        tasks[i] = saved
        do {
            try TaskRepository.shared.updateTask(saved)
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

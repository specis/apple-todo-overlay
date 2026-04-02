import Foundation

@Observable
final class TaskViewModel {

    var activeFilter: SmartList = .dueToday
    private(set) var tasks: [TodoTask] = TodoTask.mockTasks()

    var filteredTasks: [TodoTask] {
        FilterService.apply(activeFilter, to: tasks)
    }

    func toggleComplete(_ task: TodoTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].completed.toggle()
        tasks[i].completedAt = tasks[i].completed ? Date() : nil
        tasks[i].lastModified = Date()
    }
}

// MARK: - Mock data

extension TodoTask {
    static func mockTasks() -> [TodoTask] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func date(_ offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: today)!
        }

        return [
            // Overdue
            make("Review Q1 report",          due: date(-3), priority: .high),
            make("Pay electricity bill",       due: date(-1), priority: .medium),

            // Today
            make("Call dentist",               due: date(0)),
            make("Submit expense report",      due: date(0), priority: .high),
            make("Team standup notes",         due: date(0), priority: .low),

            // Tomorrow
            make("Buy groceries",              due: date(1)),
            make("Book flights",               due: date(1), priority: .medium),

            // This week
            make("Finish project proposal",    due: date(3), priority: .high),
            make("Schedule retrospective",     due: date(4), priority: .medium),

            // Next week
            make("Quarterly planning doc",     due: date(9), priority: .medium),
            make("Review pull requests",       due: date(10), priority: .low),

            // No due date
            make("Read Swift concurrency book"),
            make("Tidy desk"),

            // Recently completed
            make("Set up project repo",        due: date(-2), completed: true),
            make("Write architecture doc",     due: date(-1), priority: .medium, completed: true),
        ]
    }

    private static func make(
        _ title: String,
        due: Date? = nil,
        priority: Priority = .none,
        completed: Bool = false
    ) -> TodoTask {
        TodoTask(
            id: UUID().uuidString,
            title: title,
            notes: nil,
            dueDate: due,
            completed: completed,
            completedAt: completed ? Date() : nil,
            source: .local,
            externalId: nil,
            createdAt: Date(),
            lastModified: Date(),
            syncStatus: .synced,
            listId: nil,
            priority: priority,
            tags: []
        )
    }
}

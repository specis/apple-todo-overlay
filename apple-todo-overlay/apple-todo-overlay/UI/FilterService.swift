import Foundation

enum FilterService {

    static func apply(_ filter: SmartList, to tasks: [TodoTask]) -> [TodoTask] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let dayAfterTomorrow = cal.date(byAdding: .day, value: 2, to: today)!
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)!
        let nextWeekStart = thisWeek.end
        let nextWeekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: nextWeekStart)!
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now)!

        switch filter {
        case .all:
            return tasks.filter { !$0.completed }
        case .overdue:
            return tasks.filter { !$0.completed && due($0, before: today) }
        case .dueToday:
            return tasks.filter { !$0.completed && due($0, from: today, to: tomorrow) }
        case .dueTomorrow:
            return tasks.filter { !$0.completed && due($0, from: tomorrow, to: dayAfterTomorrow) }
        case .dueThisWeek:
            return tasks.filter { !$0.completed && due($0, from: today, to: thisWeek.end) }
        case .dueNextWeek:
            return tasks.filter { !$0.completed && due($0, from: nextWeekStart, to: nextWeekEnd) }
        case .noDueDate:
            return tasks.filter { !$0.completed && $0.dueDate == nil }
        case .recentlyCompleted:
            return tasks.filter { $0.completed && ($0.completedAt ?? .distantPast) >= sevenDaysAgo }
        }
    }

    // MARK: - Helpers

    private static func due(_ task: TodoTask, before date: Date) -> Bool {
        guard let d = task.dueDate else { return false }
        return d < date
    }

    private static func due(_ task: TodoTask, from: Date, to: Date) -> Bool {
        guard let d = task.dueDate else { return false }
        return d >= from && d < to
    }
}

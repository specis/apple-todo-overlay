enum SmartList: String, CaseIterable, Identifiable {
    case all               = "All"
    case overdue           = "Overdue"
    case dueToday          = "Today"
    case dueTomorrow       = "Tomorrow"
    case dueThisWeek       = "This Week"
    case dueNextWeek       = "Next Week"
    case noDueDate         = "No Due Date"
    case recentlyCompleted = "Recently Completed"

    var id: String { rawValue }
}

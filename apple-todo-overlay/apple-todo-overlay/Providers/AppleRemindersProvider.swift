import EventKit
import Foundation

final class AppleRemindersProvider: TaskProvider {

    private let store = EKEventStore()

    // MARK: - TaskProvider

    func isAvailable() -> Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func fetchLists() async throws -> [TaskList] {
        guard isAvailable() else { return [] }
        let now = Date()
        return store.calendars(for: .reminder).map { cal in
            TaskList(
                id: cal.calendarIdentifier,
                name: cal.title,
                source: .appleReminders,
                externalId: cal.calendarIdentifier,
                createdAt: now,
                lastModified: now
            )
        }
    }

    func fetchChanges(since date: Date) async throws -> [TodoTask] {
        guard isAvailable() else { return [] }
        let calendars = store.calendars(for: .reminder)

        // Pull incomplete reminders modified since last sync
        let incompletePredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        // Pull reminders completed since last sync
        let completedPredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: date,
            ending: Date(),
            calendars: calendars
        )

        async let incomplete = fetchReminders(matching: incompletePredicate)
        async let completed  = fetchReminders(matching: completedPredicate)
        let (inc, comp) = try await (incomplete, completed)

        let recent = inc.filter { ($0.lastModifiedDate ?? .distantPast) >= date }
        return (recent + comp).compactMap { map($0) }
    }

    func pushChanges(_ tasks: [TodoTask]) async throws {
        guard isAvailable() else { return }

        for task in tasks {
            guard
                let externalId = task.externalId,
                let reminder = store.calendarItem(withIdentifier: externalId) as? EKReminder
            else { continue }

            reminder.isCompleted  = task.completed
            reminder.completionDate = task.completed ? task.completedAt : nil
            reminder.priority     = task.priority.ekPriority
            try store.save(reminder, commit: false)
        }
        try store.commit()
    }

    // MARK: - Access

    /// Requests full access to Reminders. Returns true if granted.
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func map(_ reminder: EKReminder) -> TodoTask? {
        let dueDate = reminder.dueDateComponents.flatMap {
            Calendar.current.date(from: $0)
        }

        return TodoTask(
            id:           UUID().uuidString,
            title:        reminder.title ?? "Untitled",
            notes:        reminder.notes,
            dueDate:      dueDate,
            completed:    reminder.isCompleted,
            completedAt:  reminder.completionDate,
            source:       .appleReminders,
            externalId:   reminder.calendarItemIdentifier,
            createdAt:    reminder.creationDate ?? Date(),
            lastModified: reminder.lastModifiedDate ?? Date(),
            syncStatus:   .synced,
            listId:       reminder.calendar.calendarIdentifier,
            priority:     Priority(ekPriority: reminder.priority),
            tags:         []
        )
    }
}

// MARK: - Priority ↔ EKReminder mapping

private extension Priority {
    var ekPriority: Int {
        switch self {
        case .high:   return 1
        case .medium: return 5
        case .low:    return 9
        case .none:   return 0
        }
    }

    init(ekPriority: Int) {
        switch ekPriority {
        case 1...4: self = .high
        case 5:     self = .medium
        case 6...9: self = .low
        default:    self = .none
        }
    }
}

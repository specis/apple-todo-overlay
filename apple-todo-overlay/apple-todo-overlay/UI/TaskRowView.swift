import SwiftUI

struct TaskRowView: View {

    let task: TodoTask
    let isExpanded: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            checkboxButton
            taskDetails
            Spacer(minLength: 4)
            priorityDot
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }

    // MARK: - Subviews

    private var checkboxButton: some View {
        Button(action: onToggle) {
            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(task.completed ? Color.accentColor : Color.secondary.opacity(0.4))
                .animation(.spring(duration: 0.2), value: task.completed)
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
        // Prevent tap from propagating to the row's onTapGesture
        .onTapGesture { onToggle() }
    }

    private var taskDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(task.completed ? .tertiary : .primary)
                    .strikethrough(task.completed)
                    .animation(.easeInOut(duration: 0.15), value: task.completed)

                if isExpanded {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            if let label = dueDateLabel {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(dueDateColor)
            }

            if !task.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(task.tags) { tag in
                        TagChipView(tag: tag)
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    private var priorityDot: some View {
        Group {
            if task.priority != .none {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isExpanded
                  ? Color.primary.opacity(0.05)
                  : isHovered
                    ? Color.primary.opacity(0.04)
                    : Color.clear)
    }

    // MARK: - Helpers

    private var dueDateLabel: String? {
        guard let date = task.dueDate else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInTomorrow(date)  { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }

        let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: date)).day ?? 0
        if days < -1  { return "\(abs(days)) days ago" }
        if days < 7   { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var dueDateColor: Color {
        guard let date = task.dueDate else { return .secondary }
        if date < Calendar.current.startOfDay(for: Date()) { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .secondary
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        case .none:   return .clear
        }
    }
}

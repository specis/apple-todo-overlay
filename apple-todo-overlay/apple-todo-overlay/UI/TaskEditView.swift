import SwiftUI

struct TaskEditView: View {

    let task: TodoTask
    let allTags: [Tag]
    let onSave: (TodoTask) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var priority: Priority
    @State private var selectedTags: [Tag]
    @State private var showDeleteConfirm = false
    @FocusState private var titleFocused: Bool

    init(task: TodoTask, allTags: [Tag],
         onSave: @escaping (TodoTask) -> Void,
         onDelete: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.task = task
        self.allTags = allTags
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        _title = State(initialValue: task.title)
        _dueDate = State(initialValue: task.dueDate ?? Date())
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _priority = State(initialValue: task.priority)
        _selectedTags = State(initialValue: task.tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleField
            dueDateRow
            priorityRow
            if !allTags.isEmpty { tagRow }
            bottomRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
        .onAppear { titleFocused = true }
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Task title", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($titleFocused)
            .onSubmit { save() }
    }

    // MARK: - Due date

    private var dueDateRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if hasDueDate {
                DatePicker("", selection: Binding(
                    get: { dueDate ?? Date() },
                    set: { dueDate = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .scaleEffect(0.85, anchor: .leading)
                .frame(height: 22)

                Button {
                    hasDueDate = false
                    dueDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Set due date") {
                    hasDueDate = true
                    dueDate = Calendar.current.startOfDay(for: Date())
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Priority

    private var priorityRow: some View {
        HStack(spacing: 4) {
            ForEach([Priority.none, .low, .medium, .high], id: \.self) { p in
                Button {
                    priority = p
                } label: {
                    Text(p == .none ? "None" : p.rawValue.capitalized)
                        .font(.system(size: 11, weight: priority == p ? .semibold : .regular))
                        .foregroundStyle(priority == p ? .white : priorityLabelColor(p))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(priority == p
                                      ? priorityLabelColor(p)
                                      : priorityLabelColor(p).opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tags

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(allTags) { tag in
                    let isSelected = selectedTags.contains { $0.id == tag.id }
                    Button {
                        if isSelected {
                            selectedTags.removeAll { $0.id == tag.id }
                        } else {
                            selectedTags.append(tag)
                        }
                    } label: {
                        TagChipView(tag: tag, selected: isSelected)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            }

            Spacer()

            Button("Cancel") { onDismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("Save") { save() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
        }
    }

    // MARK: - Helpers

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var updated = task
        updated.title = title.trimmingCharacters(in: .whitespaces)
        updated.dueDate = hasDueDate ? dueDate : nil
        updated.priority = priority
        updated.tags = selectedTags
        updated.lastModified = Date()
        updated.syncStatus = .pendingUpload
        onSave(updated)
    }

    private func priorityLabelColor(_ p: Priority) -> Color {
        switch p {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        case .none:   return .secondary
        }
    }
}

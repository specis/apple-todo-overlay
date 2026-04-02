import SwiftUI

struct HUDContentView: View {

    var viewModel: TaskViewModel
    @State private var showingQuickAdd = false

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            if !viewModel.availableTags.isEmpty {
                tagFilterBar
            }
            Divider()
            taskList
            if showingQuickAdd {
                QuickAddView(isVisible: $showingQuickAdd) { parsed in
                    withAnimation(.spring(duration: 0.25)) {
                        viewModel.createTask(from: parsed)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 360, height: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onKeyPress(.escape) {
            if viewModel.editingTaskId != nil {
                viewModel.editingTaskId = nil
                return .handled
            }
            if showingQuickAdd {
                withAnimation(.spring(duration: 0.2)) { showingQuickAdd = false }
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "checklist")
                .foregroundStyle(.tint)
            Text("Tasks")
                .font(.headline)
            Spacer()
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.default, value: viewModel.filteredTasks.count)
            Button {
                withAnimation(.spring(duration: 0.2)) { showingQuickAdd.toggle() }
            } label: {
                Image(systemName: showingQuickAdd ? "xmark.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(showingQuickAdd ? Color.secondary : Color.accentColor)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var countLabel: String {
        let n = viewModel.filteredTasks.count
        return n == 1 ? "1 task" : "\(n) tasks"
    }

    // MARK: - Smart list filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SmartList.allCases) { list in
                    filterPill(list)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func filterPill(_ list: SmartList) -> some View {
        let selected = viewModel.activeFilter == list
        return Button {
            withAnimation(.spring(duration: 0.2)) {
                viewModel.activeFilter = list
                viewModel.activeTagFilter = nil
            }
        } label: {
            Text(list.rawValue)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tag filter bar

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(viewModel.availableTags) { tag in
                    let selected = viewModel.activeTagFilter?.id == tag.id
                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            viewModel.activeTagFilter = selected ? nil : tag
                        }
                    } label: {
                        TagChipView(tag: tag, selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Task list

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.filteredTasks.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.filteredTasks) { task in
                        let isEditing = viewModel.editingTaskId == task.id
                        VStack(spacing: 0) {
                            TaskRowView(
                                task: task,
                                isExpanded: isEditing,
                                onToggle: {
                                    withAnimation(.spring(duration: 0.25)) {
                                        viewModel.toggleComplete(task)
                                    }
                                },
                                onTap: {
                                    withAnimation(.spring(duration: 0.2)) {
                                        viewModel.editingTaskId = isEditing ? nil : task.id
                                    }
                                }
                            )

                            if isEditing {
                                TaskEditView(
                                    task: task,
                                    allTags: viewModel.availableTags,
                                    onSave: { updated in
                                        withAnimation(.spring(duration: 0.2)) {
                                            viewModel.updateTask(updated)
                                        }
                                    },
                                    onDelete: {
                                        withAnimation(.spring(duration: 0.2)) {
                                            viewModel.deleteTask(task)
                                        }
                                    },
                                    onDismiss: {
                                        withAnimation(.spring(duration: 0.2)) {
                                            viewModel.editingTaskId = nil
                                        }
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }

                        Divider().padding(.leading, 42)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .animation(.spring(duration: 0.25), value: viewModel.filteredTasks.map(\.id))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Nothing here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap + to add a task")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

#Preview {
    HUDContentView(viewModel: TaskViewModel())
        .frame(width: 360, height: 560)
        .background(Color.black.opacity(0.4))
}

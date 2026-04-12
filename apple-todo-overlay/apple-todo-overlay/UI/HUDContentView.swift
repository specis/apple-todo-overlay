import SwiftUI

struct HUDContentView: View {

    @Bindable var viewModel: TaskViewModel
    @State private var showingQuickAdd = false
    @State private var showingSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if showingSearch {
                searchBar
            } else {
                filterBar
                if !viewModel.availableTags.isEmpty {
                    tagFilterBar
                }
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
            if showingSearch {
                closeSearch()
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
                withAnimation(.spring(duration: 0.2)) {
                    showingSearch.toggle()
                    if showingSearch {
                        showingQuickAdd = false
                        searchFocused = true
                    } else {
                        closeSearch()
                    }
                }
            } label: {
                Image(systemName: showingSearch ? "xmark.circle.fill" : "magnifyingglass")
                    .foregroundStyle(showingSearch ? Color.secondary : Color.primary.opacity(0.6))
                    .font(.system(size: showingSearch ? 18 : 15))
            }
            .buttonStyle(.plain)
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

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("Search tasks…", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func closeSearch() {
        withAnimation(.spring(duration: 0.2)) {
            showingSearch = false
            viewModel.searchText = ""
        }
    }

    // MARK: - Smart list filter bar

    private var filterBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SmartList.allCases) { list in
                        filterPill(list)
                            .id(list)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.activeFilter) { _, newFilter in
                withAnimation(.spring(duration: 0.2)) {
                    proxy.scrollTo(newFilter, anchor: .center)
                }
            }
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
            Image(systemName: viewModel.searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(viewModel.searchText.isEmpty ? "Nothing here" : "No results")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.searchText.isEmpty ? "Tap + to add a task" : "Try a different search term")
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

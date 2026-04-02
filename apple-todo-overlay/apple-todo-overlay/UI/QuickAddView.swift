import SwiftUI

struct QuickAddView: View {

    @Binding var isVisible: Bool
    let onAdd: (ParsedInput) -> Void

    @State private var text = ""
    @State private var parsed = ParsedInput(title: "", dueDate: nil, priority: .none, tagNames: [])
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            inputRow
            if parsed.hasMetadata {
                previewRow
            }
        }
        .background(.ultraThinMaterial)
        .onChange(of: text) { _, newValue in
            parsed = NaturalLanguageParser.parse(newValue)
        }
        .onAppear { focused = true }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.tint)
                .font(.system(size: 16))

            TextField("Add task…  ! priority  # tag  'tomorrow'", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { submit() }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Preview chips

    private var previewRow: some View {
        HStack(spacing: 6) {
            if let date = parsed.dueDate {
                chip(icon: "calendar", label: label(for: date), color: .blue)
            }
            if parsed.priority != .none {
                chip(icon: "circle.fill", label: parsed.priority.rawValue.capitalized,
                     color: priorityColor(parsed.priority))
            }
            ForEach(parsed.tagNames, id: \.self) { tag in
                chip(icon: "number", label: tag, color: .purple)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func chip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func submit() {
        let result = NaturalLanguageParser.parse(text)
        guard !result.title.isEmpty else {
            dismiss()
            return
        }
        onAdd(result)
        text = ""
        focused = true  // keep field active for rapid entry
    }

    private func dismiss() {
        isVisible = false
        text = ""
    }

    // MARK: - Helpers

    private func label(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    private func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        case .none:   return .clear
        }
    }
}

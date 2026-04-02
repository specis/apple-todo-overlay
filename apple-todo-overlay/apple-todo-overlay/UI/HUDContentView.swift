import SwiftUI

// Placeholder shell — will be replaced with the real UI in task #3
struct HUDContentView: View {

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            placeholder
        }
        .frame(width: 360, height: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack {
            Image(systemName: "checklist")
                .foregroundStyle(.tint)
            Text("Tasks")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("HUD shell")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Task list UI coming in next step")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HUDContentView()
        .background(Color.black.opacity(0.3))
}

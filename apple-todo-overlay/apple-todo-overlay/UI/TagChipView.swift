import SwiftUI

struct TagChipView: View {

    let tag: Tag
    var selected: Bool = true
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(hex: tag.colour))
                .frame(width: 5, height: 5)

            Text(tag.name)
                .font(.system(size: 10))

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(selected ? Color(hex: tag.colour) : Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(selected
                      ? Color(hex: tag.colour).opacity(0.15)
                      : Color.primary.opacity(0.06))
        )
    }
}

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double(value & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Tag {
    /// Auto-assigns a colour from the palette based on the tag name.
    static func autoColour(for name: String) -> String {
        let palette = [
            "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
            "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
        ]
        return palette[abs(name.lowercased().hashValue) % palette.count]
    }
}

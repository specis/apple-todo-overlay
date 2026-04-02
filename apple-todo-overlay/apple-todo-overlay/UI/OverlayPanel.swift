import AppKit

final class OverlayPanel: NSPanel {

    static let defaultSize = NSSize(width: 360, height: 560)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: OverlayPanel.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Float above normal windows; stays visible on all Spaces and over fullscreen apps
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Transparent background so the SwiftUI material shows through
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Don't hide when the app loses focus
        hidesOnDeactivate = false

        // Let the user drag the panel by its background
        isMovableByWindowBackground = true
    }

    // Required so keyboard events (e.g. checkbox toggle) reach the panel
    override var canBecomeKey: Bool { true }
}

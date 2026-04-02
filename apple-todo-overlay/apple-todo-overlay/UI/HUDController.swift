import AppKit
import SwiftUI

final class HUDController {

    static let shared = HUDController()

    private var panel: OverlayPanel?
    private var globalMonitor: Any?

    private init() {}

    // MARK: - Setup

    func setup() {
        let panel = OverlayPanel()
        let rootView = HUDContentView()
        panel.contentView = NSHostingView(rootView: rootView)
        positionNearTopRight(panel)
        self.panel = panel

        registerGlobalHotkey()
    }

    // MARK: - Show / Hide

    func show() {
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        guard let panel else { return }
        panel.isVisible ? hide() : show()
    }

    // MARK: - Positioning

    private func positionNearTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 16
        let x = screen.visibleFrame.maxX - panel.frame.width - margin
        let y = screen.visibleFrame.maxY - panel.frame.height - margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Global hotkey (⌥ Space)
    // Requires Accessibility permission. Fails silently if not granted —
    // the menu bar icon remains the fallback toggle.

    private func registerGlobalHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌥ Space
            if event.modifierFlags.contains(.option) && event.keyCode == 49 {
                self?.toggle()
            }
        }
    }
}

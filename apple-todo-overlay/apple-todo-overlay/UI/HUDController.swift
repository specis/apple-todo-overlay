import AppKit
import ApplicationServices
import SwiftUI

@Observable
final class HUDController {

    static let shared = HUDController()

    let viewModel = TaskViewModel()
    private(set) var isVisible = false
    private(set) var accessibilityGranted = false

    private var panel: OverlayPanel?
    private var globalMonitor: Any?

    private init() {}

    // MARK: - Setup

    func setup() {
        let panel = OverlayPanel()
        let rootView = HUDContentView(viewModel: viewModel)
        panel.contentView = NSHostingView(rootView: rootView)
        positionNearTopRight(panel)
        let savedOpacity = UserDefaults.standard.object(forKey: "hudOpacity") as? Double ?? 1.0
        panel.alphaValue = CGFloat(max(0.2, min(1.0, savedOpacity)))
        self.panel = panel

        checkAndRequestAccessibility()
    }

    func setOpacity(_ value: Double) {
        panel?.alphaValue = CGFloat(value)
        UserDefaults.standard.set(value, forKey: "hudOpacity")
    }

    // MARK: - Show / Hide

    func show() {
        panel?.orderFront(nil)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func reload() {
        viewModel.load()
    }

    // MARK: - Positioning

    private func positionNearTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 16
        let x = screen.visibleFrame.maxX - panel.frame.width - margin
        let y = screen.visibleFrame.maxY - panel.frame.height - margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Accessibility + global hotkey

    /// Checks Accessibility permission. If missing, shows an alert and opens
    /// System Settings directly — more reliable than AXIsProcessTrustedWithOptions
    /// in sandboxed apps. Polls every 2 s so the hotkey activates without a restart.
    func checkAndRequestAccessibility() {
        if AXIsProcessTrusted() {
            accessibilityGranted = true
            registerGlobalHotkey()
            return
        }

        accessibilityGranted = false

        // Delay slightly so the alert appears after the app is fully on screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showAccessibilityAlert()
        }

        pollForAccessibility()
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Enable Global Hotkey"
        alert.informativeText = """
            apple-todo-overlay needs Accessibility access to use ⌃⌥Space \
            (Control+Option+Space) to toggle the HUD from any app.

            Without it you can still open the HUD from the menu bar icon \
            while it is visible.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    private func pollForAccessibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if AXIsProcessTrusted() {
                self.accessibilityGranted = true
                self.registerGlobalHotkey()
            } else {
                self.pollForAccessibility()
            }
        }
    }

    /// Global hotkey: ⌃⌥Space (Control + Option + Space).
    /// Less likely to conflict with system shortcuts or common launcher apps
    /// that typically bind to ⌥Space or ⌘Space.
    private func registerGlobalHotkey() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.control, .option] && event.keyCode == 49 {
                DispatchQueue.main.async { self?.toggle() }
            }
        }
    }
}

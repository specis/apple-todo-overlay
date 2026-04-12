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
    private var localMonitor: Any?

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
        registerArrowKeyMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
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

    /// Local arrow key monitor — cycles through smart list filter pills.
    /// Runs only while the HUD is visible. Skips when a text field has focus
    /// (search bar, quick-add) so typing is unaffected.
    private func registerArrowKeyMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            // Let text input fields handle their own arrow keys
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextField || responder is NSTextView {
                return event
            }
            let all = SmartList.allCases
            switch event.keyCode {
            case 123: // left arrow
                if let i = all.firstIndex(of: self.viewModel.activeFilter), i > 0 {
                    DispatchQueue.main.async {
                        self.viewModel.activeFilter = all[i - 1]
                    }
                }
                return nil
            case 124: // right arrow
                if let i = all.firstIndex(of: self.viewModel.activeFilter), i < all.count - 1 {
                    DispatchQueue.main.async {
                        self.viewModel.activeFilter = all[i + 1]
                    }
                }
                return nil
            default:
                return event
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

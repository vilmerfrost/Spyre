import AppKit
import SwiftUI

/// Shows the first-run screen in its own window.
/// An AppKit window, because on macOS 14 a menubar-only (`LSUIElement`) app has no SwiftUI hook
/// that opens a scene at launch. `SPEC.md` 4.8.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: () -> Void = {}

    /// Opens the window, or brings it to the front when it is open.
    func show(tokens: Tokens, onStart: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        if window == nil {
            let content = WelcomeView(onStart: onStart).environment(\.tokens, tokens)
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "Welcome to Spyre"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose()
    }
}

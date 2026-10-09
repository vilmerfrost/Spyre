import AppKit
import SwiftUI

/// One AppKit window that hosts a SwiftUI view: the main window and the first-run window.
/// AppKit, not a SwiftUI scene: a menubar-only (`LSUIElement`) app on macOS 14 has no reliable SwiftUI
/// hook that opens a scene from AppKit code (launch, reopen, the global shortcut). `SPEC.md` 3.2, 4.8.
@MainActor
final class HostedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let style: NSWindow.StyleMask
    private var onClose: () -> Void = {}

    init(title: String, style: NSWindow.StyleMask) {
        self.title = title
        self.style = style
    }

    /// Opens the window, or brings it to the front when it is open.
    /// - Parameter pinned: keeps the window above other apps, on every Space, until it becomes key. For the first-run
    ///   window: macOS can refuse to activate Spyre (another app is frontmost), and then the window
    ///   opens behind that app or on another Space. `SPEC.md` 4.8.
    func show(pinned: Bool = false, content: () -> some View, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        let window = self.window ?? makeWindow(NSHostingController(rootView: content()))
        self.window = window
        if pinned, !window.isKeyWindow {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow(_ controller: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = style
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.center()
        return window
    }

    /// The user reached the window. It now behaves like a normal window.
    func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .normal
        window?.collectionBehavior = [.moveToActiveSpace]
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose()
    }
}

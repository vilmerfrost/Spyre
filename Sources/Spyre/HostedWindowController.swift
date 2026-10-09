import AppKit
import SwiftUI

/// One AppKit window that hosts a SwiftUI view: the main window and the first-run window.
/// AppKit, not a SwiftUI scene: a menubar-only (`LSUIElement`) app on macOS 14 has no reliable SwiftUI
/// hook that opens a scene from AppKit code (launch, reopen, the global shortcut). `SPEC.md` 3.2, 4.8.
///
/// The content runs under the title bar, so the atmospheric background fills the whole window.
/// The window appearance always matches the active theme, so the title bar and system controls match too.
@MainActor
final class HostedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let style: NSWindow.StyleMask
    private var appearance: NSAppearance?
    private var onClose: () -> Void = {}

    init(title: String, style: NSWindow.StyleMask) {
        self.title = title
        self.style = style
    }

    /// Opens the window, or brings it to the front when it is open.
    /// - Parameters:
    ///   - pinned: keeps the window above other apps, on every Space, until it becomes key. For the first-run
    ///     window: macOS can refuse to activate Spyre (another app is frontmost), and then the window
    ///     opens behind that app or on another Space. `SPEC.md` 4.8.
    ///   - defaultSize: the content size of a new resizable window. `nil` sizes the window to its content.
    ///   - appearance: the macOS appearance of the active theme.
    func show(
        pinned: Bool = false, defaultSize: CGSize? = nil, appearance: NSAppearance?,
        content: () -> some View, onClose: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self.appearance = appearance
        let window = self.window ?? makeWindow(content(), defaultSize: defaultSize)
        self.window = window
        window.appearance = appearance
        if pinned, !window.isKeyWindow {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    /// Sets the macOS appearance. Called when the theme follows a system appearance change.
    func setAppearance(_ appearance: NSAppearance?) {
        self.appearance = appearance
        window?.appearance = appearance
    }

    func close() {
        window?.close()
    }

    private func makeWindow(_ content: some View, defaultSize: CGSize?) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        if defaultSize != nil { controller.sizingOptions = [.minSize] }
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = style.union(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.appearance = appearance
        window.delegate = self
        if let defaultSize { window.setContentSize(defaultSize) }
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

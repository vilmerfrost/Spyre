import AppKit
import SpyreCore
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
    private var limits: SizeLimits?
    /// The last content height the view asked for. Kept for a window that opens after the request.
    private var contentHeight: CGFloat = 0

    /// The size range of a resizable window that fits its content height. `DESIGN.md` 2.5.
    struct SizeLimits {
        var min: CGSize
        var max: CGSize
        /// macOS stores the window frame under this name (`NSWindow` frame autosave), not in `config.json`.
        var autosaveName: String
    }

    init(title: String, style: NSWindow.StyleMask) {
        self.title = title
        self.style = style
    }

    /// Opens the window, or brings it to the front when it is open.
    /// - Parameters:
    ///   - pinned: keeps the window above other apps, on every Space, until it becomes key. For the first-run
    ///     window: macOS can refuse to activate Spyre (another app is frontmost), and then the window
    ///     opens behind that app or on another Space. `SPEC.md` 4.8.
    ///   - limits: the size range of a resizable window, and its frame autosave name.
    ///     `nil` sizes the window to its content.
    ///   - appearance: the macOS appearance of the active theme.
    func show(
        pinned: Bool = false, limits: SizeLimits? = nil, appearance: NSAppearance?,
        content: () -> some View, onClose: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self.appearance = appearance
        self.limits = limits
        let window = self.window ?? makeWindow(content(), limits: limits)
        self.window = window
        fitHeight(contentHeight)
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

    /// Fits the window height to its content, within the size limits. The top edge stays put.
    /// - Parameter contentHeight: the height the SwiftUI content needs below the title bar.
    func fitHeight(_ contentHeight: CGFloat) {
        self.contentHeight = contentHeight
        guard let window, let limits, contentHeight > 0 else { return }
        let titleBar = window.frame.height - window.contentLayoutRect.height
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let frame = WindowFrameRule.fitted(
            window.frame, contentHeight: contentHeight + titleBar,
            minHeight: limits.min.height, maxHeight: limits.max.height, visible: visible
        )
        if frame != window.frame { window.setFrame(frame, display: true) }
    }

    private func makeWindow(_ content: some View, limits: SizeLimits?) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        if limits != nil { controller.sizingOptions = [] }
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = style.union(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.appearance = appearance
        window.delegate = self
        guard let limits else {
            window.center()
            return window
        }
        window.contentMinSize = limits.min
        window.contentMaxSize = limits.max
        if !window.setFrameUsingName(limits.autosaveName) {
            window.setContentSize(CGSize(width: limits.max.width, height: limits.min.height))
            window.center()
        }
        let screens = NSScreen.screens.map(\.visibleFrame)
        window.setFrame(WindowFrameRule.clamped(window.frame, screens: screens), display: false)
        window.setFrameAutosaveName(limits.autosaveName)
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

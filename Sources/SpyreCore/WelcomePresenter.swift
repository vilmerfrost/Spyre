import Foundation

/// Decides when the first-run screen shows. The view only renders. `SPEC.md` 4.8.
@MainActor
public final class WelcomePresenter {
    /// `true` while the first-run screen should be on screen.
    public private(set) var isPresented = false
    /// `true` when the window may be on screen: the screen is presented and the app finished launching.
    /// A window shown before launch ends cannot come to the front.
    public var showsWindow: Bool { isPresented && launched }
    /// What opening Spyre again (Finder, Raycast, `open`, Dock, the shortcut) brings to the front.
    public var reopenTarget: ReopenTarget { isPresented ? .welcome : .mainWindow }
    private var decided = false
    private var launched = false
    private let file: ConfigFile

    public init(file: ConfigFile) {
        self.file = file
    }

    /// Call with each loaded config. Only the first load decides, so a later reload never opens the screen.
    public func configLoaded(_ config: SpyreConfig) {
        guard !decided else { return }
        decided = true
        isPresented = !config.welcomeSeen
    }

    /// Call once, when `applicationDidFinishLaunching` runs.
    public func appLaunched() {
        launched = true
    }

    /// The "Show welcome screen" menu item. It does not change `welcomeSeen`.
    public func reopen() {
        isPresented = true
    }

    /// The window closed without "Start watching". This does not count as seen.
    public func closed() {
        isPresented = false
    }

    /// The "Start watching" button. Closes the screen, then writes `welcomeSeen: true` off the main actor.
    public func startWatching() async throws {
        isPresented = false
        let file = file
        try await Task.detached { try file.markWelcomeSeen() }.value
    }
}

/// The window that opening Spyre again brings to the front. `SPEC.md` 3.2.
public enum ReopenTarget: Sendable, Equatable {
    /// The first-run screen is still open. It stays first until the user answers it.
    case welcome
    case mainWindow
}

import Foundation

/// Decides when the first-run screen shows. The view only renders. `SPEC.md` 4.8.
@MainActor
public final class WelcomePresenter {
    /// `true` while the first-run screen should be on screen.
    public private(set) var isPresented = false
    private var decided = false
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

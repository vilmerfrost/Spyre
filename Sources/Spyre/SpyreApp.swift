import os
import SpyreCore
import SwiftUI

@main
struct SpyreApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(model)
                .environment(\.tokens, model.tokens)
        } label: {
            MenuBarLabel(waitingCount: model.sessions.waitingCount, icon: model.tokens.icon("icon.app"))
        }
        .menuBarExtraStyle(.window)

        Window("Spyre", id: "main") {
            MainWindowView()
                .environment(model)
                .environment(\.tokens, model.tokens)
        }
    }
}

/// App state for the UI. Sessions come from `SessionStore`, which runs off the main actor.
@MainActor
@Observable
final class AppModel {
    private(set) var sessions: [SessionRecord] = []
    private(set) var config = SpyreConfig.default
    /// Problems in `config.json`. The menubar window shows them.
    private(set) var configWarnings: [String] = []
    var tokens = Tokens.builtIn("light")
    /// Decides when the first-run screen shows. `SPEC.md` 4.8.
    private let welcome: WelcomePresenter
    private let welcomeWindow = WelcomeWindowController()
    private let makeAdapters: @Sendable (SpyreConfig) -> [any AgentAdapter]
    private var store: SessionStore?
    private var configWatcher: ConfigWatcher?
    private static let logger = Logger(subsystem: "io.github.vilmerfrost.spyre", category: "config")

    /// - Parameter makeAdapters: builds the adapters once the first config is loaded.
    init(
        makeAdapters: @escaping @Sendable (SpyreConfig) -> [any AgentAdapter] = AppModel.realAdapters,
        configFile: ConfigFile = ConfigFile(folder: ConfigFile.defaultFolder())
    ) {
        self.makeAdapters = makeAdapters
        welcome = WelcomePresenter(file: configFile)
        configWatcher = ConfigWatcher(file: configFile) { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    /// Claude Code and Codex, reading the real `~/.claude` and `~/.codex`.
    nonisolated static func realAdapters(config: SpyreConfig) -> [any AgentAdapter] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let processes = SystemProcessScanner()
        return [
            ClaudeCodeAdapter(claudeRoot: home.appendingPathComponent(".claude"), processes: processes, config: config),
            CodexAdapter(codexRoot: home.appendingPathComponent(".codex"), processes: processes, config: config),
        ]
    }

    private func apply(_ result: ConfigLoadResult) {
        config = result.config
        configWarnings = result.warnings
        for warning in result.warnings {
            Self.logger.warning("\(warning, privacy: .public)")
        }
        if let store {
            Task { await store.update(config: result.config) }
        } else {
            start(SessionStore(adapters: makeAdapters(result.config), config: result.config))
            welcome.configLoaded(result.config)
            syncWelcomeWindow()
        }
    }

    /// The "Show welcome screen" menu item. It does not reset `welcomeSeen`.
    func showWelcome() {
        welcome.reopen()
        syncWelcomeWindow()
    }

    private func startWatching() {
        Task {
            do {
                try await welcome.startWatching()
            } catch {
                Self.logger.warning("Cannot write welcomeSeen to config.json.")
            }
        }
        welcomeWindow.close()
    }

    private func syncWelcomeWindow() {
        guard welcome.isPresented else { return welcomeWindow.close() }
        welcomeWindow.show(
            tokens: tokens,
            onStart: { [weak self] in self?.startWatching() },
            onClose: { [weak self] in self?.welcome.closed() }
        )
    }

    private func start(_ store: SessionStore) {
        self.store = store
        Task.detached { await store.run() }
        Task { [weak self] in
            for await sessions in store.updates { self?.sessions = sessions }
        }
    }
}

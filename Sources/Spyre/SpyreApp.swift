import AppKit
import os
import SpyreCore
import SwiftUI

@main
struct SpyreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let model = delegate.model
        MenuBarExtra {
            MenuContentView()
                .environment(model)
                .environment(\.tokens, model.tokens)
        } label: {
            MenuBarLabel(waitingCount: model.sessions.waitingCount, icon: model.tokens.icon("icon.app"))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the app state, so AppKit events (launch, reopen) reach it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.launchFinished()
    }

    /// Opening Spyre again while it runs: Finder, Raycast, `open`, or a click on the Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.reopen()
        return false
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
    private let welcomeWindow = HostedWindowController(title: "Welcome to Spyre", style: [.titled, .closable])
    private let mainWindow = HostedWindowController(
        title: "Spyre", style: [.titled, .closable, .miniaturizable, .resizable]
    )
    private var hotkey: GlobalHotkey?
    /// A problem with the global shortcut. Shown with the config warnings.
    private var hotkeyWarning: String?
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
        hotkey = GlobalHotkey { [weak self] in self?.showMainWindow() }
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
        let policy: NSApplication.ActivationPolicy = result.config.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        hotkeyWarning = hotkey?.register(result.config.hotkey)
        configWarnings = result.warnings + [hotkeyWarning].compactMap { $0 }
        for warning in configWarnings {
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

    func launchFinished() {
        welcome.appLaunched()
        syncWelcomeWindow()
    }

    /// Opening the app again brings the first-run window back while it is open, else the main window.
    func reopen() {
        switch welcome.reopenTarget {
        case .welcome: syncWelcomeWindow()
        case .mainWindow: showMainWindow()
        }
    }

    /// The "Open Spyre" button, the global shortcut, and reopen.
    func showMainWindow() {
        mainWindow.show {
            MainWindowView().environment(self).environment(\.tokens, tokens)
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
        guard welcome.showsWindow else { return welcomeWindow.close() }
        let shortcut = config.hotkey.displayString
        welcomeWindow.show(pinned: true) {
            WelcomeView(shortcut: shortcut, onStart: { [weak self] in self?.startWatching() })
                .environment(\.tokens, tokens)
        } onClose: { [weak self] in
            self?.welcome.closed()
        }
    }

    private func start(_ store: SessionStore) {
        self.store = store
        Task.detached { await store.run() }
        Task { [weak self] in
            for await sessions in store.updates { self?.sessions = sessions }
        }
    }
}

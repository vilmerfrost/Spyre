import SpyreCore
import SwiftUI

@main
struct SpyreApp: App {
    @State private var model = AppModel(adapter: FakeAdapter())

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

/// App state for the UI. The scaffold uses the fake adapter. Real adapters come in later PRs.
@MainActor
@Observable
final class AppModel {
    private(set) var sessions: [SessionRecord] = []
    private(set) var config = SpyreConfig.default
    /// Problems in `config.json`. The menubar window shows them.
    private(set) var configWarnings: [String] = []
    var tokens = Tokens.builtIn("light")
    private let adapter: any AgentAdapter
    private var configWatcher: ConfigWatcher?

    init(adapter: any AgentAdapter, configFile: ConfigFile = ConfigFile(folder: ConfigFile.defaultFolder())) {
        self.adapter = adapter
        configWatcher = ConfigWatcher(file: configFile) { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
        Task { await refresh() }
    }

    private func apply(_ result: ConfigLoadResult) {
        config = result.config
        configWarnings = result.warnings
    }

    func refresh() async {
        sessions = await adapter.refresh().sessions
    }
}

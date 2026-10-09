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
    var tokens = Tokens.builtIn("light")
    private let adapter: any AgentAdapter

    init(adapter: any AgentAdapter) {
        self.adapter = adapter
        Task { await refresh() }
    }

    func refresh() async {
        sessions = await adapter.refresh().sessions
    }
}

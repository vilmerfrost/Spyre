import SpyreCore
import SwiftUI

/// The menubar label: app icon and the waiting count.
struct MenuBarLabel: View {
    let waitingCount: Int
    let icon: String

    var body: some View {
        if waitingCount > 0 {
            Label("\(waitingCount)", systemImage: icon)
                .accessibilityLabel("Spyre, \(waitingCount) waiting")
        } else {
            Image(systemName: icon)
                .accessibilityLabel("Spyre")
        }
    }
}

/// The short session list in the menubar window.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.md")) {
            Text("\(model.sessions.waitingCount) waiting")
                .font(tokens.font("stat").weight(.light).monospacedDigit())
                .foregroundStyle(tokens.color("color.text.primary"))
            SessionListView(sessions: model.sessions)
            if let warning = model.configWarnings.first {
                Label(warning, systemImage: tokens.icon("icon.status.waiting"))
                    .font(tokens.font("label"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
            }
            Button("Open Spyre") { openWindow(id: "main") }
                .buttonStyle(.borderedProminent)
                .tint(tokens.color("color.accent"))
        }
        .padding(tokens.value("space.lg"))
        .frame(width: tokens.value("size.menu.width"))
        .background(tokens.color("color.background.base"))
    }
}

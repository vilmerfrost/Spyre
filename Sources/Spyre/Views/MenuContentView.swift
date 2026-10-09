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

/// The menubar window: the count line, the top rows (Needs you first, then Working), and the way into Spyre.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .frame(width: tokens.value("size.menu.width"))
        .background {
            ZStack {
                tokens.color("color.background.base")
                AtmosphereView(density: .dense)
            }
        }
    }

    private func content(now: Date) -> some View {
        let rows = model.sessions.menuRows(limit: Int(tokens.value("size.menu.maxRows")))
        let hidden = model.sessions.count - rows.count
        return VStack(alignment: .leading, spacing: tokens.value("space.md")) {
            CountLine(counts: SessionCounts(model.sessions), compact: true)
            if rows.isEmpty {
                Text(model.sessions.isEmpty ? "Quiet out here. No sessions running." : "Nothing needs you.")
                    .font(tokens.font("body"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
            } else {
                Panel {
                    ForEach(Array(rows.enumerated()), id: \.element.row.id) { index, entry in
                        if index > 0 { RowDivider() }
                        SessionRow(row: entry.row, group: entry.group, now: now, compact: true)
                            .background(tokens.color("color.surface.waiting").opacity(entry.group == .waiting ? 1 : 0))
                    }
                }
            }
            if hidden > 0 {
                Text("\(hidden) more in Spyre")
                    .font(tokens.font("label").monospacedDigit())
                    .foregroundStyle(tokens.color("color.text.secondary"))
            }
            if let warning = model.configWarnings.first {
                Label(warning, systemImage: tokens.icon("icon.flag.noActivity"))
                    .font(tokens.font("label"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: tokens.value("space.sm")) {
                Button("Open Spyre") { model.showMainWindow() }
                    .buttonStyle(SpyreButtonStyle(kind: .primary))
                Text(model.config.hotkey.displayString)
                    .font(tokens.font("label").monospacedDigit())
                    .foregroundStyle(tokens.color("color.text.secondary"))
                    .accessibilityLabel("Shortcut \(model.config.hotkey.displayString)")
                Spacer()
                Button("Show welcome screen") { model.showWelcome() }
                    .buttonStyle(SpyreButtonStyle(kind: .quiet))
                    .accessibilityLabel("Show welcome screen")
            }
            .padding(.top, tokens.value("space.xs"))
        }
        .padding(tokens.value("space.lg"))
    }
}

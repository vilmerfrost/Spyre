import AppKit
import SpyreCore
import SwiftUI

/// The menubar label: a monochrome template icon, and the waiting count from 1 ("9+" from 10).
/// It never changes color. `SPEC.md` 4.1.
struct MenuBarLabel: View {
    let waitingCount: Int
    let icon: String

    var body: some View {
        Group {
            if let text = MenuBarBadge.text(waitingCount: waitingCount) {
                Label(text, systemImage: icon)
            } else {
                Image(systemName: icon)
            }
        }
        .accessibilityLabel(MenuBarBadge.accessibilityLabel(waitingCount: waitingCount))
    }
}

/// The menubar window: the count line, the top rows (Needs you first, then Working), and the way into Spyre.
/// Its height fits the content.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    /// The row with keyboard focus. The rows are one keyboard stop; ↑/↓ move inside it. Esc closes the window
    /// (the system handles it).
    @State private var cursor: RadarItem?
    @FocusState private var rowsFocused: Bool

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
        let sessions = model.visibleSessions(now: now)
        let panel = MenuPanelContent(sessions, limit: Int(tokens.value("size.menu.maxRows")))
        return VStack(alignment: .leading, spacing: tokens.value("space.md")) {
            if sessions.isEmpty {
                Text(EmptyRadar.title)
                    .font(tokens.font("rowTitle"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
            } else {
                CountLine(content: CountLineContent(SessionCounts(sessions)), compact: true)
            }
            if !panel.rows.isEmpty {
                rows(panel, now: now)
            }
            if let more = panel.moreText {
                Button(more) { model.showMainWindow() }
                    .buttonStyle(.plain)
                    .font(tokens.font("control").monospacedDigit())
                    .foregroundStyle(tokens.color("color.text.secondary"))
                    .accessibilityHint("Opens the main window.")
            }
            if let warning = model.configWarnings.first {
                Label(warning, systemImage: tokens.icon("icon.flag.noActivity"))
                    .font(tokens.font("label"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer.padding(.top, tokens.value("space.xs"))
        }
        .padding(tokens.value("space.lg"))
    }

    private func rows(_ panel: MenuPanelContent, now: Date) -> some View {
        let navigation = RadarNavigation(rows: panel.rows.map(\.row))
        let ring = rowsFocused ? navigation.resolve(cursor) : nil
        return Panel {
            ForEach(Array(panel.rows.enumerated()), id: \.element.row.id) { index, entry in
                if index > 0 { RowDivider() }
                SessionRow(row: entry.row, group: entry.group, now: now, compact: true)
                    .background(tokens.color("color.surface.waiting").opacity(entry.group == .waiting ? 1 : 0))
                    .focusRingAnchor(ring == .row(entry.row.id))
            }
        }
        .focusRingOverlay()
        .focusable()
        .focused($rowsFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
            guard let key = RadarKey(press) else { return .ignored }
            switch navigation.handle(key, focused: navigation.resolve(cursor)) {
            case .focus(let item): cursor = item
            case .showApp(let id):
                if let row = panel.rows.first(where: { $0.row.id == id })?.row { model.showApp(row.session) }
            default: break
            }
            return .handled
        }
    }

    /// "Open Spyre", the shortcut hint, then "Show welcome screen" and "Quit Spyre".
    /// The last two do not fit next to each other at `size.menu.width`, so they sit in a "More" menu.
    private var footer: some View {
        HStack(spacing: tokens.value("space.sm")) {
            Button("Open Spyre") { model.showMainWindow() }
                .buttonStyle(SpyreButtonStyle(kind: .primary))
            Text(model.config.hotkey.displayString)
                .font(tokens.font("hint"))
                .foregroundStyle(tokens.color("color.text.secondary"))
                .accessibilityLabel("Shortcut \(model.config.hotkey.displayString)")
            Spacer()
            Menu {
                Button("Show welcome screen") { model.showWelcome() }
                Divider()
                Button("Quit Spyre") { model.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Text("More")
                    .font(tokens.font("control"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
    }
}

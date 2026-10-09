import SpyreCore
import SwiftUI

/// One session row, about 44 points high. Status shows as glyph, color, and text, never color alone.
/// A click runs "Show app". Hover shows two quiet actions and the detail chevron. The detail line opens below.
/// A compact row (menubar window) shows the status note on line 2, so the title keeps its room.
struct SessionRow: View {
    let row: SessionListRow
    /// The group the row shows in. A nested child can have another status.
    let group: StatusGroup
    let now: Date
    var compact = false
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @State private var hovering = false

    private var session: SessionRecord { row.session }
    /// Idle and done rows need no action. Their titles step back, so active rows lead.
    private var isQuiet: Bool { session.status == .idle || session.status == .done }
    private var isSelected: Bool { !compact && model.selectedSessionID == session.id }
    private var hasFolder: Bool { !session.workingDirectory.isEmpty }

    var body: some View {
        let text = SessionRowText(session, homeDirectory: NSHomeDirectory(), isNested: row.isNested)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                leading
                lines(text)
            }
            .frame(minHeight: tokens.value(compact ? "size.row.compactHeight" : "size.row.height"))
            if isSelected {
                // The detail line starts at the title edge.
                SessionDetailView(session: session)
                    .padding(.leading, tokens.value("size.status.column") + tokens.value("space.md"))
                    .padding(.bottom, tokens.value("space.md"))
            }
        }
        .padding(.horizontal, tokens.value("space.md"))
        .background(background)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(tokens.color("color.accent"))
                    .frame(width: tokens.value("size.selection.line"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.showApp(session) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: tokens.value("motion.duration.fast")), value: hovering)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(text))
        .accessibilityAction(named: "Show app") { model.showApp(session) }
        .accessibilityAction(named: "Open folder in Finder") { model.openFolder(session.workingDirectory) }
        .accessibilityAction(named: "Copy path") { model.copy(session.workingDirectory) }
        .accessibilityAction(named: isSelected ? "Hide details" : "Show details") { model.toggleDetail(session) }
    }

    /// Line 1 (title, note or hover actions, time) and line 2.
    private func lines(_ text: SessionRowText) -> some View {
        VStack(alignment: .leading, spacing: tokens.value("space.xxs")) {
            // The time sits on line 1's baseline in every row, one-line and two-line alike.
            HStack(alignment: .firstTextBaseline, spacing: tokens.value("space.sm")) {
                Text(text.title)
                    .font(tokens.font("rowTitle"))
                    .foregroundStyle(tokens.color(isQuiet ? "color.text.secondary" : "color.text.primary"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: tokens.value("space.sm"))
                trailing
            }
            lineTwo(text)
        }
    }

    private var background: Color {
        if isSelected { return tokens.color("color.surface.controlSelected") }
        return tokens.color("color.surface.rowHover").opacity(hovering ? 1 : 0)
    }

    /// The same actions as the hover buttons, with exact labels. `SPEC.md` 4.3.
    @ViewBuilder private var menu: some View {
        Button("Show app") { model.showApp(session) }
        Button("Open folder in Finder") { model.openFolder(session.workingDirectory) }
            .disabled(!hasFolder)
        Button("Copy path") { model.copy(session.workingDirectory) }
            .disabled(!hasFolder)
        if !compact {
            Divider()
            Button(isSelected ? "Hide details" : "Show details") { model.toggleDetail(session) }
        }
    }

    /// The status glyph column. A nested child puts the corner arrow in the parent's glyph column and its own
    /// glyph at the parent's title edge, so the child title is indented by `size.child.indent`.
    @ViewBuilder private var leading: some View {
        if row.isNested {
            Image(systemName: tokens.icon("icon.child"))
                .font(tokens.font("label"))
                .foregroundStyle(tokens.color("color.text.secondary"))
                .frame(width: tokens.value("size.status.column"))
                .padding(.trailing, tokens.value("space.md"))
            StatusGlyph(status: session.status, column: "size.icon.status")
                .padding(.trailing, tokens.value("size.child.indent") - tokens.value("size.icon.status"))
        } else {
            StatusGlyph(status: session.status)
                .padding(.trailing, tokens.value("space.md"))
        }
    }

    /// Line 2: project · branch · agent · mode, then tags. The main window puts a small monochrome agent mark
    /// before the agent name (a placeholder token, `DESIGN.md` 5.4). The menubar rows stay text only.
    private func lineTwo(_ text: SessionRowText) -> some View {
        HStack(spacing: tokens.value("space.xs")) {
            if compact, let note {
                Text(note.text)
                    .font(tokens.font("label"))
                    .foregroundStyle(tokens.color(note.color))
                    .fixedSize()
            }
            Group {
                if compact {
                    Text(text.detail)
                } else {
                    let parts = text.detailParts
                    Text(parts.lead)
                        + Text(Image(systemName: tokens.icon("icon.agent.\(session.agent.rawValue)")))
                            .font(.system(size: tokens.value("size.icon.agent")))
                        + Text(" " + parts.agentAndMode)
                }
            }
            .font(tokens.font("label"))
            .foregroundStyle(tokens.color("color.text.secondary"))
            .lineLimit(1)
            .truncationMode(.tail)
            ForEach(text.tags, id: \.self) { RowTag(text: $0).fixedSize() }
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(alignment: .firstTextBaseline, spacing: tokens.value("space.sm")) {
            if hovering, !compact {
                HStack(spacing: tokens.value("space.xxs")) {
                    RowIconButton(label: "Show app", icon: "icon.action.showApp") { model.showApp(session) }
                    if hasFolder {
                        RowIconButton(label: "Open folder", icon: "icon.action.openFolder") {
                            model.openFolder(session.workingDirectory)
                        }
                    }
                }
                .transition(.opacity)
            } else if let note, !compact {
                Text(note.text)
                    .font(tokens.font("reason"))
                    .foregroundStyle(tokens.color(note.color))
                    .lineLimit(1)
            }
            Text(RelativeTime.short(from: session.lastActivity, to: now))
                .font(tokens.font("label").monospacedDigit())
                .foregroundStyle(tokens.color("color.text.secondary"))
                .frame(minWidth: tokens.value("size.row.height"), alignment: .trailing)
            if !compact {
                RowIconButton(
                    label: isSelected ? "Hide details" : "Show details", icon: "icon.disclosure",
                    rotation: isSelected ? 90 : 0
                ) { model.toggleDetail(session) }
                .opacity(hovering || isSelected ? 1 : 0)
            }
        }
        .fixedSize()
    }

    /// The text before the time: the waiting reason, the no-activity flag, or a status the group does not say.
    private var note: (text: String, color: String)? {
        if let waiting = session.waitingText { return (waiting, "color.status.waiting") }
        if session.hasNoActivityFlag(now: now, config: model.config) {
            return ("No activity", "color.flag.noActivity")
        }
        if session.status == .starting || session.status.group != group {
            return (session.status.title, "color.status.\(session.status.tokenName)")
        }
        return nil
    }

    private func accessibilityText(_ text: SessionRowText) -> String {
        var parts = [text.title, session.waitingText.map { "Needs you, \($0)" } ?? session.status.title, text.detail]
        parts += text.tags
        parts.append("last activity \(RelativeTime.short(from: session.lastActivity, to: now)) ago")
        return parts.joined(separator: ", ")
    }
}

/// A quiet icon button with a tooltip and a `size.hoverButton` hit area.
struct RowIconButton: View {
    let label: String
    let icon: String
    var rotation: Double = 0
    let action: () -> Void
    @Environment(\.tokens) private var tokens
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tokens.icon(icon))
                .font(tokens.font("control"))
                .rotationEffect(.degrees(rotation))
                .foregroundStyle(tokens.color(hovering ? "color.text.primary" : "color.text.secondary"))
                .frame(width: tokens.value("size.hoverButton"), height: tokens.value("size.hoverButton"))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The hit area may reach past line 1. It must not make the line taller.
        .padding(.vertical, -tokens.value("space.xs"))
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The detail line of a selected row: label and value pairs. Never message content. `SPEC.md` 4.2.
struct SessionDetailView: View {
    let session: SessionRecord
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens

    var body: some View {
        Grid(
            alignment: .leading, horizontalSpacing: tokens.value("space.md"), verticalSpacing: tokens.value("space.xxs")
        ) {
            ForEach(session.detailItems(formatDate: Self.format), id: \.label) { item in
                GridRow {
                    Text(item.label)
                        .gridColumnAlignment(.leading)
                    HStack(spacing: tokens.value("space.xs")) {
                        Text(item.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        if let copy = item.copyValue {
                            Button { model.copy(copy) } label: {
                                Image(systemName: tokens.icon("icon.action.copy"))
                            }
                            .buttonStyle(.plain)
                            .help("Copy session ID")
                            .accessibilityLabel("Copy session ID")
                        }
                    }
                }
            }
        }
        .font(tokens.font("label"))
        .foregroundStyle(tokens.color("color.text.secondary"))
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

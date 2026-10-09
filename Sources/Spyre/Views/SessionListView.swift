import SpyreCore
import SwiftUI

/// The count line: big calm numbers with tabular digits. Only "needs you" uses the waiting color,
/// and only when it is not zero. All three counts always show, so the line never shifts. `SPEC.md` 4.2.
struct CountLine: View {
    let counts: SessionCounts
    var compact = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: tokens.value(compact ? "space.md" : "space.lg")) {
            item(counts.needsYou, "needs you", number: counts.needsYou > 0 ? "color.status.waiting" : muted)
            item(counts.working, "working", number: counts.working > 0 ? "color.text.primary" : muted)
            item(counts.idle, "idle", number: muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counts.needsYou) need you, \(counts.working) working, \(counts.idle) idle")
    }

    private let muted = "color.text.secondary"

    private func item(_ value: Int, _ label: String, number: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: tokens.value("space.xs")) {
            Text("\(value)")
                .font(tokens.font(compact ? "countCompact" : "count").monospacedDigit())
                .foregroundStyle(tokens.color(number))
                .contentTransition(.numericText())
            Text(label)
                .font(tokens.font("body"))
                .foregroundStyle(tokens.color("color.text.secondary"))
        }
    }
}

/// The full session list in the Radar section: one panel per status group.
/// Idle and Done are folded behind a disclosure row. `SPEC.md` 4.2.
struct SessionListView: View {
    let sessions: [SessionRecord]
    let now: Date
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
            ForEach(sessions.sections(expanded: model.expandedGroups)) { section in
                VStack(alignment: .leading, spacing: tokens.value("space.sm")) {
                    if section.isCollapsible {
                        DisclosureHeader(section: section) { toggle(section.group) }
                    } else {
                        GroupHeader(section: section)
                    }
                    if !section.visibleRows.isEmpty {
                        panel(section)
                    }
                }
            }
        }
    }

    private func panel(_ section: SessionSection) -> some View {
        let waiting = section.group == .waiting
        return Panel(
            surface: waiting ? "color.surface.waiting" : "color.surface.row",
            border: waiting ? "color.border.waiting" : "color.border.row"
        ) {
            ForEach(Array(section.visibleRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { RowDivider() }
                SessionRow(row: row, group: section.group, now: now)
            }
        }
    }

    private func toggle(_ group: StatusGroup) {
        withAnimation(.snappy(duration: tokens.duration("motion.duration.normal", reduceMotion: reduceMotion))) {
            if model.expandedGroups.contains(group) {
                model.expandedGroups.remove(group)
            } else {
                model.expandedGroups.insert(group)
            }
        }
    }
}

/// A group header: the group title and its count.
private struct GroupHeader: View {
    let section: SessionSection
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack(spacing: tokens.value("space.xs")) {
            Text(section.group.title)
            Text("\(section.count)").monospacedDigit()
        }
        .font(tokens.font("section"))
        .foregroundStyle(tokens.color(section.group == .waiting ? "color.status.waiting" : "color.text.secondary"))
        .padding(.leading, tokens.value("space.xs"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The header of a folded-by-default group. A click folds or unfolds the group.
private struct DisclosureHeader: View {
    let section: SessionSection
    let action: () -> Void
    @Environment(\.tokens) private var tokens
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: tokens.value("space.xs")) {
                Image(systemName: tokens.icon("icon.disclosure"))
                    .font(tokens.font("tag"))
                    .rotationEffect(.degrees(section.isExpanded ? 90 : 0))
                Text(section.group.title)
                Text("\(section.count)").monospacedDigit()
            }
            .font(tokens.font("section"))
            .foregroundStyle(tokens.color(hovering ? "color.text.primary" : "color.text.secondary"))
            .padding(.leading, tokens.value("space.xs"))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(section.group.title), \(section.count) sessions")
        .accessibilityValue(section.isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(section.isExpanded ? "Hides these sessions." : "Shows these sessions.")
    }
}

/// One session row, about 44 points high. Status shows as glyph, color, and text, never color alone.
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

    var body: some View {
        let text = SessionRowText(session, homeDirectory: NSHomeDirectory(), isNested: row.isNested)
        HStack(spacing: tokens.value("space.md")) {
            if row.isNested {
                Image(systemName: tokens.icon("icon.child"))
                    .font(tokens.font("label"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
                    .frame(width: tokens.value("size.status.column"))
            }
            StatusGlyph(status: session.status)
            VStack(alignment: .leading, spacing: tokens.value("space.xxs")) {
                Text(text.title)
                    .font(tokens.font("rowTitle"))
                    .foregroundStyle(tokens.color(isQuiet ? "color.text.secondary" : "color.text.primary"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: tokens.value("space.xs")) {
                    if compact, let note {
                        Text(note.text)
                            .font(tokens.font("label").weight(.medium))
                            .foregroundStyle(tokens.color(note.color))
                            .fixedSize()
                    }
                    Text(text.detail)
                        .font(tokens.font("label"))
                        .foregroundStyle(tokens.color("color.text.secondary"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ForEach(text.tags, id: \.self) { RowTag(text: $0).fixedSize() }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: tokens.value("space.sm"))
            trailing
        }
        .padding(.horizontal, tokens.value("space.md"))
        .frame(minHeight: tokens.value(compact ? "size.row.compactHeight" : "size.row.height"))
        .background(tokens.color("color.surface.rowHover").opacity(hovering ? 1 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: tokens.value("motion.duration.fast")), value: hovering)
        .contextMenu {
            Button("Open Folder in Finder") { model.openFolder(session.workingDirectory) }
                .disabled(session.workingDirectory.isEmpty)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(text))
        .accessibilityAction(named: "Open folder") { model.openFolder(session.workingDirectory) }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: tokens.value("space.sm")) {
            if hovering, !session.workingDirectory.isEmpty {
                Button {
                    model.openFolder(session.workingDirectory)
                } label: {
                    Label("Open folder", systemImage: tokens.icon("icon.action.openFolder"))
                }
                .buttonStyle(SpyreButtonStyle(kind: .quiet))
                .transition(.opacity)
            } else if !compact, let note {
                Text(note.text)
                    .font(tokens.font("control"))
                    .foregroundStyle(tokens.color(note.color))
                    .lineLimit(1)
            }
            Text(RelativeTime.short(from: session.lastActivity, to: now))
                .font(tokens.font("label").monospacedDigit())
                .foregroundStyle(tokens.color("color.text.secondary"))
                .frame(minWidth: tokens.value("size.row.height"), alignment: .trailing)
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

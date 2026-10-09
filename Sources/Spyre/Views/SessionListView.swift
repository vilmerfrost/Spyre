import SpyreCore
import SwiftUI

/// The count line. When something needs you: big calm numbers with tabular digits, and only "needs you"
/// uses the waiting color. When nothing needs you: "Nothing needs you." and a short summary. `SPEC.md` 4.2.
struct CountLine: View {
    let content: CountLineContent
    var compact = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        Group {
            switch content {
            case .attention(let counts):
                HStack(alignment: .firstTextBaseline, spacing: tokens.value(compact ? "space.md" : "space.lg")) {
                    item(counts.needsYou, "needs you", number: "color.status.waiting")
                    item(counts.working, "working", number: counts.working > 0 ? "color.text.primary" : muted)
                    item(counts.idle, "idle", number: muted)
                }
            case .calm(let summary):
                HStack(alignment: .firstTextBaseline, spacing: tokens.value("space.sm")) {
                    Text(CountLineContent.calmTitle)
                        .font(tokens.font(compact ? "calmCompact" : "calm"))
                    if !summary.isEmpty {
                        Text(summary).font(tokens.font("body").monospacedDigit())
                    }
                }
                .foregroundStyle(tokens.color(muted))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    private let muted = "color.text.secondary"

    /// A number and its label on one shared baseline, `space.xs` apart.
    private func item(_ value: Int, _ label: String, number: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: tokens.value("space.xs")) {
            Text("\(value)")
                .font(tokens.font(compact ? "countCompact" : "count").monospacedDigit())
                .foregroundStyle(tokens.color(number))
                .contentTransition(.numericText())
            Text(label)
                .font(tokens.font("body"))
                .foregroundStyle(tokens.color(muted))
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
        let fold = IdleFold(now: now, after: model.config.idleFoldAfter, isExpanded: model.earlierExpanded)
        VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
            ForEach(sessions.sections(expanded: model.expandedGroups, idleFold: fold)) { section in
                VStack(alignment: .leading, spacing: tokens.value("space.sm")) {
                    if section.isCollapsible {
                        DisclosureHeader(section: section) { toggle(section.group) }
                    } else {
                        GroupHeader(section: section)
                    }
                    if !section.visibleRows.isEmpty || section.showsEarlier {
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
            if section.showsEarlier {
                if !section.visibleRows.isEmpty { RowDivider() }
                EarlierRow(count: section.earlierCount, isExpanded: section.isEarlierExpanded) {
                    withFold { model.earlierExpanded.toggle() }
                }
                ForEach(section.visibleEarlierRows) { row in
                    RowDivider()
                    SessionRow(row: row, group: section.group, now: now)
                }
            }
        }
    }

    private func toggle(_ group: StatusGroup) {
        withFold {
            if model.expandedGroups.contains(group) {
                model.expandedGroups.remove(group)
            } else {
                model.expandedGroups.insert(group)
            }
        }
    }

    private func withFold(_ change: () -> Void) {
        withAnimation(.snappy(duration: tokens.duration("motion.duration.normal", reduceMotion: reduceMotion)), change)
    }
}

/// The "Earlier N" row at the end of the Idle panel: idle sessions older than `idleFoldAfter`. `SPEC.md` 4.2.
/// The chevron sits in the status glyph column, so the label starts at the title edge.
private struct EarlierRow: View {
    let count: Int
    let isExpanded: Bool
    let action: () -> Void
    @Environment(\.tokens) private var tokens
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: tokens.value("space.md")) {
                Image(systemName: tokens.icon("icon.disclosure"))
                    .font(tokens.font("tag"))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: tokens.value("size.status.column"))
                HStack(spacing: tokens.value("space.xs")) {
                    Text("Earlier")
                    Text("\(count)").monospacedDigit()
                }
                Spacer()
            }
            .font(tokens.font("section"))
            .foregroundStyle(tokens.color(hovering ? "color.text.primary" : "color.text.secondary"))
            .padding(.horizontal, tokens.value("space.md"))
            .frame(minHeight: tokens.value("size.row.disclosureHeight"))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Earlier, \(count) sessions")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
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
        HStack(spacing: 0) {
            leading
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
                HStack(spacing: tokens.value("space.xs")) {
                    if compact, let note {
                        Text(note.text)
                            .font(tokens.font("label"))
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
        }
        .padding(.horizontal, tokens.value("space.md"))
        .frame(minHeight: tokens.value(compact ? "size.row.compactHeight" : "size.row.height"))
        .background(tokens.color("color.surface.rowHover").opacity(hovering ? 1 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: tokens.value("motion.duration.fast")), value: hovering)
        .contextMenu {
            Button("Open folder in Finder") { model.openFolder(session.workingDirectory) }
                .disabled(session.workingDirectory.isEmpty)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(text))
        .accessibilityAction(named: "Open folder in Finder") { model.openFolder(session.workingDirectory) }
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

    @ViewBuilder private var trailing: some View {
        HStack(alignment: .firstTextBaseline, spacing: tokens.value("space.sm")) {
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
                    .font(tokens.font("reason"))
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

import SpyreCore
import SwiftUI

/// The count line. When something needs you: big calm numbers with tabular digits, and only "needs you"
/// uses the waiting color. When nothing needs you: "Nothing needs you." and a short summary. `SPEC.md` 4.2.
struct CountLine: View {
    let content: CountLineContent
    var compact = false
    @Environment(\.tokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .contentTransition(reduceMotion ? .identity : .numericText())
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
    /// The main window focus. The list is one keyboard stop; ↑/↓ move inside it.
    var focus: FocusState<MainFocus?>.Binding
    /// Scrolls the list to an item.
    var scrollTo: (RadarItem) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rotor

    /// The row order while the pointer is over the list. Rows never move under the pointer. `SPEC.md` 4.2.
    @State private var frozen: [SessionSection]?
    /// The item with the keyboard focus inside the list.
    @State private var cursor: RadarItem?
    /// The ring shows for keyboard focus only. A click hides it.
    @State private var keyboardDriven = false

    var body: some View {
        let fold = IdleFold(now: now, after: model.config.idleFoldAfter, isExpanded: model.earlierExpanded)
        let fresh = sessions.sections(expanded: model.expandedGroups, idleFold: fold)
        let shown = frozen.map { fresh.frozen(to: $0) } ?? fresh
        let navigation = RadarNavigation(sections: shown)
        let ring = focus.wrappedValue == .list && keyboardDriven ? navigation.resolve(cursor) : nil
        let titles = Dictionary(sessions.map { ($0.id, Self.title($0)) }) { first, _ in first }
        VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
            ForEach(shown) { section in
                VStack(alignment: .leading, spacing: tokens.value("space.sm")) {
                    Group {
                        if section.isCollapsible {
                            DisclosureHeader(section: section) { toggle(section.group) }
                        } else {
                            GroupHeader(section: section)
                        }
                    }
                    .focusRingAnchor(ring == .header(section.group))
                    .id(RadarItem.header(section.group))
                    if !section.visibleRows.isEmpty || section.showsEarlier {
                        panel(section, ring: ring, titles: titles)
                    }
                }
            }
        }
        .focusRingOverlay()
        .focusable()
        .focused(focus, equals: .list)
        .focusEffectDisabled()
        .onKeyPress(keys: RadarKey.keys) { press in
            guard let key = RadarKey(press) else { return .ignored }
            keyboardDriven = true
            return apply(navigation.handle(key, focused: navigation.resolve(cursor)), shown: shown)
        }
        .onHover { inside in frozen = inside ? shown : nil }
        .simultaneousGesture(TapGesture().onEnded { keyboardDriven = false })
        .accessibilityElement(children: .contain)
        .accessibilityRotor("Needs you") {
            ForEach(shown.filter { $0.group == .waiting }.flatMap(\.visibleRows)) { row in
                AccessibilityRotorEntry(Text(titles[row.id] ?? ""), id: row.id, in: rotor)
            }
        }
    }

    private static func title(_ record: SessionRecord) -> String {
        SessionRowText(record, homeDirectory: NSHomeDirectory()).title
    }

    private func apply(_ command: RadarCommand, shown: [SessionSection]) -> KeyPress.Result {
        let rows = shown.flatMap { $0.rows + $0.earlierRows }
        switch command {
        case .none: return .handled
        case .focus(let item):
            cursor = item
            scrollTo(item)
        case .toggleGroup(let group): toggle(group)
        case .toggleEarlier: withFold { model.earlierExpanded.toggle() }
        case .showApp(let id): if let row = rows.first(where: { $0.id == id }) { model.showApp(row.session) }
        case .toggleDetail(let id):
            if let row = rows.first(where: { $0.id == id }) { model.toggleDetail(row.session) }
        case .focusSwitcher: focus.wrappedValue = .switcher
        }
        return .handled
    }

    private func panel(_ section: SessionSection, ring: RadarItem?, titles: [String: String]) -> some View {
        let waiting = section.group == .waiting
        return Panel(
            surface: waiting ? "color.surface.waiting" : "color.surface.row",
            border: waiting ? "color.border.waiting" : "color.border.row"
        ) {
            ForEach(Array(section.visibleRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { RowDivider() }
                sessionRow(row, section: section, ring: ring, titles: titles)
            }
            if section.showsEarlier {
                if !section.visibleRows.isEmpty { RowDivider() }
                EarlierRow(count: section.earlierCount, isExpanded: section.isEarlierExpanded) {
                    withFold { model.earlierExpanded.toggle() }
                }
                .focusRingAnchor(ring == .earlier)
                .id(RadarItem.earlier)
                ForEach(section.visibleEarlierRows) { row in
                    RowDivider()
                    sessionRow(row, section: section, ring: ring, titles: titles)
                }
            }
        }
    }

    private func sessionRow(
        _ row: SessionListRow, section: SessionSection, ring: RadarItem?, titles: [String: String]
    ) -> some View {
        let parent = row.isNested ? row.session.parentID.flatMap { titles[$0] } : nil
        return SessionRow(row: row, group: section.group, now: now, parentTitle: parent)
            .focusRingAnchor(ring == .row(row.id))
            .id(RadarItem.row(row.id))
            .accessibilityRotorEntry(id: row.id, in: rotor)
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
        .accessibilityLabel(RadarSpeech.disclosureLabel("Earlier", count: count))
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
        .accessibilityLabel(RadarSpeech.disclosureLabel(section.group.title, count: section.count))
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(section.isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(section.isExpanded ? "Hides these sessions." : "Shows these sessions.")
    }
}

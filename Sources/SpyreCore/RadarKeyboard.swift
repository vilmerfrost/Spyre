import Foundation

/// One keyboard stop in the Radar list: a group header, the "Earlier" row, or a session row. `SPEC.md` 4.2.
public enum RadarItem: Hashable, Sendable {
    case header(StatusGroup)
    case earlier
    case row(String)
}

/// A key the Radar list handles. Other keys (Tab, type-to-filter) are not handled.
public enum RadarKey: Sendable {
    case up, down, left, right, space, `return`, escape
}

/// What a key press does. The view applies it.
public enum RadarCommand: Sendable, Equatable {
    case none
    /// Move the keyboard focus to this item.
    case focus(RadarItem)
    /// Fold or unfold a collapsible group.
    case toggleGroup(StatusGroup)
    /// Fold or unfold "Earlier" in the Idle group.
    case toggleEarlier
    case showApp(String)
    case toggleDetail(String)
    /// Move the keyboard focus to the section switcher.
    case focusSwitcher
}

/// The keyboard model of the Radar list: a pure state machine, so it is testable. `SPEC.md` 4.2.
///
/// ↑/↓ move through headers and rows and stop at the ends. →/← unfold and fold a disclosure row.
/// ← on a child row moves to its parent. Space or Return on a disclosure row toggles it.
/// Return on a row runs "Show app".
/// Space on a row toggles its detail line. Esc moves the focus to the section switcher.
public struct RadarNavigation: Sendable, Equatable {
    /// One stop, in screen order.
    public struct Entry: Sendable, Equatable {
        public var item: RadarItem
        /// Where ← goes: the parent row of a nested child. `nil` for other items.
        public var parent: RadarItem?
        /// `nil` when the item cannot fold. Else `true` when it is unfolded.
        public var isExpanded: Bool?

        public init(item: RadarItem, parent: RadarItem? = nil, isExpanded: Bool? = nil) {
            self.item = item
            self.parent = parent
            self.isExpanded = isExpanded
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The stops of the main window list: each group header, then its visible rows, "Earlier", and its rows.
    public init(sections: [SessionSection]) {
        var entries: [Entry] = []
        for section in sections {
            entries.append(Entry(item: .header(section.group), isExpanded: section.isCollapsible
                ? section.isExpanded : nil))
            entries += Self.rows(section.visibleRows)
            if section.showsEarlier {
                entries.append(Entry(item: .earlier, isExpanded: section.isEarlierExpanded))
                entries += Self.rows(section.visibleEarlierRows)
            }
        }
        self.entries = entries
    }

    /// The stops of the menubar window: its rows only.
    public init(rows: [SessionListRow]) {
        entries = Self.rows(rows)
    }

    private static func rows(_ rows: [SessionListRow]) -> [Entry] {
        rows.map { row in
            Entry(item: .row(row.id), parent: row.isNested ? row.session.parentID.map(RadarItem.row) : nil)
        }
    }

    /// The item that keeps the focus after the list changed. A focused item that is gone gives the item now at
    /// its old place, or the last item. `nil` only for an empty list.
    public func resolve(_ focused: RadarItem?, previous: RadarNavigation? = nil) -> RadarItem? {
        if let focused, entries.contains(where: { $0.item == focused }) { return focused }
        guard !entries.isEmpty else { return nil }
        let old = focused.flatMap { item in previous?.entries.firstIndex { $0.item == item } } ?? 0
        return entries[min(old, entries.count - 1)].item
    }

    public func handle(_ key: RadarKey, focused: RadarItem?) -> RadarCommand {
        if key == .escape { return .focusSwitcher }
        guard let index = focused.flatMap({ item in entries.firstIndex { $0.item == item } }) else {
            return entries.first.map { .focus($0.item) } ?? .none
        }
        let entry = entries[index]
        switch key {
        case .up: return index > 0 ? .focus(entries[index - 1].item) : .none
        case .down: return index + 1 < entries.count ? .focus(entries[index + 1].item) : .none
        case .right: return entry.isExpanded == false ? toggle(entry.item) : .none
        case .left:
            if entry.isExpanded == true { return toggle(entry.item) }
            return entry.parent.map { .focus($0) } ?? .none
        case .space:
            if entry.isExpanded != nil { return toggle(entry.item) }
            if case .row(let id) = entry.item { return .toggleDetail(id) }
            return .none
        case .return:
            if entry.isExpanded != nil { return toggle(entry.item) }
            if case .row(let id) = entry.item { return .showApp(id) }
            return .none
        case .escape: return .focusSwitcher
        }
    }

    private func toggle(_ item: RadarItem) -> RadarCommand {
        switch item {
        case .header(let group): .toggleGroup(group)
        case .earlier: .toggleEarlier
        case .row: .none
        }
    }
}

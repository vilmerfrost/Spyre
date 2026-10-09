import Foundation

/// The process facts "Show app" needs. The app reads them with `proc_pidinfo` and `NSRunningApplication`.
/// Tests inject a fake tree. It never holds process arguments or environment variables.
public protocol ProcessTree: Sendable {
    /// The parent process ID, or `nil` when the process is gone or cannot be read.
    func parent(of pid: Int32) -> Int32?
    /// `true` when the process is a regular app: an `.app` bundle with the regular activation policy.
    func isRegularApp(_ pid: Int32) -> Bool
}

/// What "Show app" does for one row. `SPEC.md` 4.3.
public enum ShowAppAction: Sendable, Equatable {
    /// Activate this app process.
    case activate(pid: Int32)
    /// Open this URL with `NSWorkspace`, for example a Claude desktop deep link.
    case openURL(String)
    /// Nothing better was found: show the session's folder in Finder.
    case openFolder(String)
    /// Nothing can be shown.
    case none
}

/// Finds the app that hosts a session. Read-only: it reads parent process IDs and app facts only.
public enum ShowAppResolver {
    /// The parent chain stops after this many steps, so a loop in bad data can never hang.
    static let maxDepth = 64

    /// `false`: the Claude desktop deep link is not used. See `desktopDeepLink(sessionID:)`.
    public static let desktopDeepLinkVerified = false

    /// - Parameter useDesktopDeepLink: open the Claude desktop deep link for desktop rows instead of walking
    ///   the process chain. Off by default (`desktopDeepLinkVerified`).
    public static func resolve(
        _ session: SessionRecord, tree: any ProcessTree, useDesktopDeepLink: Bool = desktopDeepLinkVerified
    ) -> ShowAppAction {
        if useDesktopDeepLink, session.host == .desktop, let url = desktopDeepLink(sessionID: session.id) {
            return .openURL(url)
        }
        if let pid = session.processID, let app = firstRegularApp(from: pid, tree: tree) {
            return .activate(pid: app)
        }
        return session.workingDirectory.isEmpty ? .none : .openFolder(session.workingDirectory)
    }

    /// The first process from `pid` up the parent chain that is a regular app. The process itself counts.
    public static func firstRegularApp(from pid: Int32, tree: any ProcessTree) -> Int32? {
        var current: Int32? = pid
        var seen = Set<Int32>()
        while let next = current, next > 1, seen.count < maxDepth, seen.insert(next).inserted {
            if tree.isRegularApp(next) { return next }
            current = tree.parent(of: next)
        }
        return nil
    }

    /// `claude://code/continue?session=<id>` (undocumented).
    ///
    /// UNVERIFIED, not used. A read-only look at the installed Claude desktop app (October 2026) showed that its
    /// handler accepts only `session=last` or a desktop session ID of the form `local_…`. A Claude Code registry
    /// `sessionId` (a UUID) does not match, so the link would do nothing. Desktop rows activate the Claude app
    /// through the process chain instead.
    public static func desktopDeepLink(sessionID: String) -> String? {
        guard !sessionID.isEmpty,
              let value = sessionID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(["-", "_"]))
        else { return nil }
        return "claude://code/continue?session=\(value)"
    }
}

/// One label and value in a row's detail line. `SPEC.md` 4.2.
public struct SessionDetailItem: Sendable, Equatable {
    public var label: String
    public var value: String
    /// The full value to copy, when the item has a copy button (the session ID).
    public var copyValue: String?

    public init(label: String, value: String, copyValue: String? = nil) {
        self.label = label
        self.value = value
        self.copyValue = copyValue
    }
}

extension SessionRecord {
    /// The detail line: Path, Started, Host, Waiting reason, Session ID (last 8 characters), Agent version.
    /// Empty parts are left out. Never message content.
    /// - Parameter formatDate: formats `startedAt`. The app passes a locale-aware formatter.
    public func detailItems(formatDate: (Date) -> String) -> [SessionDetailItem] {
        var items: [SessionDetailItem] = []
        if !workingDirectory.isEmpty { items.append(.init(label: "Path", value: workingDirectory)) }
        if let startedAt { items.append(.init(label: "Started", value: formatDate(startedAt))) }
        if let host { items.append(.init(label: "Host", value: host.title)) }
        if let waitingText { items.append(.init(label: "Waiting reason", value: waitingText)) }
        if let shortID { items.append(.init(label: "Session ID", value: shortID, copyValue: id)) }
        if agent == .codex, let version = agentVersion?.trimmingCharacters(in: .whitespaces), !version.isEmpty {
            items.append(.init(label: "Agent version", value: version))
        }
        return items
    }

    /// The last 8 characters of the session ID. `nil` for Spyre's own placeholder IDs, which name a PID or folder.
    var shortID: String? {
        guard !id.isEmpty, !id.hasPrefix("claude-pid-"), !id.hasPrefix("claude-child-"), !id.hasPrefix("codex:cwd:")
        else { return nil }
        return String(id.suffix(8))
    }
}

extension Array where Element == SessionSection {
    /// The sections with the row order of `previous`, while the pointer is over the list. `SPEC.md` 4.2.
    ///
    /// A row that showed before keeps its group and place, with its new data. A new row goes to the end of its own
    /// group. A row that is gone is removed. Folding and "Earlier" follow the new sections.
    public func frozen(to previous: [SessionSection]) -> [SessionSection] {
        var place: [String: (group: StatusGroup, index: Int, earlier: Bool)] = [:]
        for section in previous {
            for (index, row) in section.rows.enumerated() { place[row.id] = (section.group, index, false) }
            for (index, row) in section.earlierRows.enumerated() { place[row.id] = (section.group, index, true) }
        }
        let all = flatMap { section in (section.rows + section.earlierRows).map { (section, $0) } }
        var result = self
        for index in result.indices {
            result[index].rows = []
            result[index].earlierRows = []
        }
        func put(_ row: SessionListRow, _ group: StatusGroup, earlier: Bool, template: SessionSection) {
            if let at = result.firstIndex(where: { $0.group == group }) {
                if earlier { result[at].earlierRows.append(row) } else { result[at].rows.append(row) }
                return
            }
            var section = template
            section.group = group
            section.rows = earlier ? [] : [row]
            section.earlierRows = earlier ? [row] : []
            section.isCollapsible = group.isCollapsedByDefault
            section.isExpanded = previous.first { $0.group == group }?.isExpanded ?? !section.isCollapsible
            result.append(section)
        }
        let known = all.filter { place[$0.1.id] != nil }
            .sorted { lhs, rhs in
                let (a, b) = (place[lhs.1.id], place[rhs.1.id])
                return (a?.earlier == true ? 1 : 0, a?.index ?? 0) < (b?.earlier == true ? 1 : 0, b?.index ?? 0)
            }
        for (section, row) in known {
            guard let spot = place[row.id] else { continue }
            put(row, spot.group, earlier: spot.earlier, template: section)
        }
        for (section, row) in all where place[row.id] == nil {
            put(row, section.group, earlier: section.earlierRows.contains { $0.id == row.id }, template: section)
        }
        return result.filter { !$0.rows.isEmpty || !$0.earlierRows.isEmpty }.sorted { $0.group < $1.group }
    }
}

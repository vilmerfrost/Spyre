import Foundation

/// The text one session row shows. Views render it. They do not decide it. `SPEC.md` 4.2.
public struct SessionRowText: Sendable, Equatable {
    /// Line 1: the session title, else the project name, else the agent name.
    public var title: String
    /// The project folder name. `~` for the home folder. `nil` when the folder is not known yet.
    public var project: String?
    /// The git branch. `nil` when there is none, and for a detached `HEAD`.
    public var branch: String?
    /// The agent name, for example `Claude Code`.
    public var agent: String
    /// Short tags after line 2, for example `exec` or `experimental`.
    public var tags: [String]

    /// - Parameters:
    ///   - homeDirectory: the user's home folder. A session in it shows `~` as the project.
    ///   - isNested: the row sits under its parent. The corner arrow then says "child", so the
    ///     "child session" tag is left out. "experimental" stays.
    public init(_ record: SessionRecord, homeDirectory: String, isNested: Bool = false) {
        let project = Self.project(record.workingDirectory, homeDirectory: homeDirectory)
        let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = !title.isEmpty ? title : (project ?? record.agent.title)
        self.project = project
        self.branch = Self.branch(record.branch)
        self.agent = record.agent.title
        let tags = isNested ? record.tags.filter { $0 != "child session" } : record.tags
        self.tags = tags + (record.isStale ? ["stale"] : [])
    }

    /// Line 2: project · branch · agent. Empty parts are left out.
    /// The project is left out when the title already is the project name.
    public var detail: String {
        [project == title ? nil : project, branch, agent].compactMap { $0 }.joined(separator: " · ")
    }

    static func project(_ path: String, homeDirectory: String) -> String? {
        let folder = normalized(path)
        guard !folder.isEmpty else { return nil }
        if folder == normalized(homeDirectory) { return "~" }
        let name = URL(fileURLWithPath: folder).lastPathComponent
        return name.isEmpty || name == "/" ? folder : name
    }

    static func branch(_ branch: String?) -> String? {
        let value = branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty || value == "HEAD" ? nil : value
    }

    private static func normalized(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let standard = (path as NSString).standardizingPath
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}

extension AgentType {
    /// The agent name the UI shows.
    public var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

extension SessionStatus {
    /// The status as a short label. Rows and accessibility labels use it. Status is never color alone.
    public var title: String {
        switch self {
        case .starting: "Starting…"
        case .working: "Working"
        case .waiting: "Needs you"
        case .idle: "Idle"
        case .done: "Done"
        case .unknown: "Unknown"
        }
    }
}

extension SessionRecord {
    /// Why the session waits, in sentence case, for example "Permission prompt". `nil` when not `waiting`.
    public var waitingText: String? {
        guard status == .waiting else { return nil }
        let reason = waitingReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let first = reason.first else { return "Needs input" }
        return first.uppercased() + reason.dropFirst()
    }
}

/// Short relative times with a fixed form: "20 s", "4 min", "3 h", "2 d".
public enum RelativeTime {
    public static func short(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds) s"
        case ..<3_600: return "\(seconds / 60) min"
        case ..<86_400: return "\(seconds / 3_600) h"
        default: return "\(seconds / 86_400) d"
        }
    }
}

/// The numbers in the count line. `SPEC.md` 4.2.
public struct SessionCounts: Sendable, Equatable {
    /// `waiting` sessions. The same number as the menubar badge.
    public var needsYou: Int
    /// `working` and `starting` sessions.
    public var working: Int
    public var idle: Int

    public init(_ sessions: [SessionRecord]) {
        needsYou = sessions.waitingCount
        working = sessions.filter { $0.status.group == .working }.count
        idle = sessions.filter { $0.status == .idle }.count
    }
}

/// One group in the session list, ready to render. `SPEC.md` 4.2.
public struct SessionSection: Sendable, Equatable, Identifiable {
    public var group: StatusGroup
    public var rows: [SessionListRow]
    /// `true` for a group that can be folded behind a disclosure row: Idle and Done.
    public var isCollapsible: Bool
    /// `false` when a collapsible group is folded. Its rows are then hidden.
    public var isExpanded: Bool

    public var id: StatusGroup { group }
    /// The number in the group header: top-level sessions. A nested child counts in its own status only.
    public var count: Int { rows.filter { !$0.isNested }.count }
    /// The rows to show. Empty while the group is folded.
    public var visibleRows: [SessionListRow] { isExpanded ? rows : [] }
}

extension StatusGroup {
    /// The group header text.
    public var title: String {
        switch self {
        case .waiting: "Needs you"
        case .working: "Working"
        case .idle: "Idle"
        case .unknown: "Unknown"
        case .done: "Done"
        }
    }

    /// Idle and Done are folded by default. Reason: they need no action. `SPEC.md` 4.2.
    public var isCollapsedByDefault: Bool { self == .idle || self == .done }
}

extension Array where Element == SessionRecord {
    /// The session list as sections. A folded group keeps its header and count.
    /// - Parameter expanded: the folded-by-default groups the user opened. Spyre keeps it in memory only.
    public func sections(expanded: Set<StatusGroup> = []) -> [SessionSection] {
        grouped().map { group, rows in
            let collapsible = group.isCollapsedByDefault
            return SessionSection(
                group: group, rows: rows, isCollapsible: collapsible,
                isExpanded: !collapsible || expanded.contains(group)
            )
        }
    }

    /// The short list in the menubar window: Needs you first, then Working, at most `limit` rows.
    /// Each row comes with the group it shows in. Children stay under their parent.
    /// Idle, Unknown, and Done rows are left out.
    public func menuRows(limit: Int) -> [(group: StatusGroup, row: SessionListRow)] {
        let rows = grouped().filter { $0.group == .waiting || $0.group == .working }
            .flatMap { group, rows in rows.map { (group: group, row: $0) } }
        return Swift.Array(rows.prefix(Swift.max(0, limit)))
    }
}

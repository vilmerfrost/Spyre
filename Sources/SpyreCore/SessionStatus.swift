import Foundation

/// The status of one agent session. `SPEC.md` 4.4 defines each value.
public enum SessionStatus: String, Sendable, CaseIterable, Codable {
    /// The session exists, but no source has given a good read yet.
    case starting
    case working
    case waiting
    case idle
    case done
    case unknown

    /// Only `waiting` counts in the menubar badge.
    public var countsInBadge: Bool { self == .waiting }

    /// The list group that shows this status.
    public var group: StatusGroup {
        switch self {
        case .waiting: .waiting
        case .starting, .working: .working
        case .idle: .idle
        case .unknown: .unknown
        case .done: .done
        }
    }
}

/// A group in the session list. Groups show in declaration order.
public enum StatusGroup: Int, Sendable, CaseIterable, Comparable {
    case waiting, working, idle, unknown, done

    public static func < (lhs: StatusGroup, rhs: StatusGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The agent type that a session belongs to.
public enum AgentType: String, Sendable, Codable {
    case claudeCode
    case codex
}

/// The app or mode that hosts a session. The detail line calls it "Host".
public enum SessionHost: String, Sendable, Codable, CaseIterable {
    /// Claude Code in a terminal (`entrypoint` `cli`).
    case cli
    /// Claude Code inside the Claude desktop app (`entrypoint` `claude-desktop`).
    case desktop
    /// Claude Code inside VS Code (`entrypoint` `claude-vscode`).
    case vscode
    /// The Codex terminal UI.
    case codex
    /// A `codex exec` run.
    case exec

    /// The Claude Code registry `entrypoint` value. `nil` for an unknown or missing value.
    public init?(claudeEntrypoint: String?) {
        switch claudeEntrypoint {
        case "cli": self = .cli
        case "claude-desktop": self = .desktop
        case "claude-vscode": self = .vscode
        default: return nil
        }
    }

    /// The text the detail line shows.
    public var title: String {
        switch self {
        case .cli: "CLI"
        case .desktop: "Desktop"
        case .vscode: "VS Code"
        case .codex: "Codex"
        case .exec: "exec"
        }
    }
}

/// How a session was started. `SPEC.md` 6.3 defines both kinds.
public enum SessionKind: String, Sendable, Codable {
    /// Started outside Spyre. Always read-only.
    case observed
    /// Started by Spyre through an official SDK. Not in the MVP.
    case owned
}

/// One session, as an adapter reports it to the app.
public struct SessionRecord: Sendable, Identifiable, Equatable {
    public var id: String
    public var agent: AgentType
    public var kind: SessionKind
    public var workingDirectory: String
    /// The session title, when the agent has one: the Claude Code registry `name` (`SPEC.md` 5.1 A) or the Codex
    /// `threads.title` (5.2 A). Shown locally only. Never logged or stored.
    public var title: String?
    public var branch: String?
    public var status: SessionStatus
    public var waitingReason: String?
    public var lastActivity: Date
    public var parentID: String?
    /// The adapter refresh timed out. The row shows its last state with a "stale" mark.
    public var isStale: Bool
    /// A child session (`SPEC.md` 4.6, EXPERIMENTAL). With no `parentID`, the row shows "child, no parent".
    public var isChildSession: Bool
    /// A short mode label for the row, for example `exec` for a `codex exec` run. `nil` for an interactive session.
    public var label: String?
    /// The agent process, when known: the Claude Code registry `pid`, a child process, or the Codex TUI.
    /// "Show app" walks its parent chain (`SPEC.md` 4.3).
    public var processID: Int32?
    /// The app or mode that hosts the session, when known. The detail line shows it as "Host".
    public var host: SessionHost?
    /// When the session started: registry `startedAt` (Claude Code), thread `created_at_ms` (Codex).
    public var startedAt: Date?
    /// The agent version that wrote the session. Codex `cli_version` only.
    public var agentVersion: String?

    public init(
        id: String,
        agent: AgentType,
        kind: SessionKind = .observed,
        workingDirectory: String,
        title: String? = nil,
        branch: String? = nil,
        status: SessionStatus,
        waitingReason: String? = nil,
        lastActivity: Date,
        parentID: String? = nil,
        isStale: Bool = false,
        isChildSession: Bool = false,
        label: String? = nil,
        processID: Int32? = nil,
        host: SessionHost? = nil,
        startedAt: Date? = nil,
        agentVersion: String? = nil
    ) {
        self.id = id
        self.agent = agent
        self.kind = kind
        self.workingDirectory = workingDirectory
        self.title = title
        self.branch = branch
        self.status = status
        self.waitingReason = waitingReason
        self.lastActivity = lastActivity
        self.parentID = parentID
        self.isStale = isStale
        self.isChildSession = isChildSession
        self.label = label
        self.processID = processID
        self.host = host
        self.startedAt = startedAt
        self.agentVersion = agentVersion
    }

    /// The last path component of the working directory.
    public var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    /// Short row tags: the mode label, then the child-session marks (`SPEC.md` 4.6). Empty for most sessions.
    public var tags: [String] {
        var tags = label.map { [$0] } ?? []
        if isChildSession { tags += [parentID == nil ? "child, no parent" : "child session", "experimental"] }
        return tags
    }

    /// `true` when a working session had no activity for longer than the threshold.
    public func hasNoActivityFlag(now: Date, config: SpyreConfig) -> Bool {
        status == .working && now.timeIntervalSince(lastActivity) > config.noActivityThreshold
    }
}

extension Array where Element == SessionRecord {
    /// The number shown in the menubar badge.
    public var waitingCount: Int { filter { $0.status.countsInBadge }.count }

    /// The session list in display order. `SPEC.md` 4.2.
    ///
    /// Top-level rows are grouped by status. Inside a group, the newest activity comes first.
    /// A child session whose parent is in the list shows directly under its parent, in the parent's group,
    /// newest first. A child whose parent is not in the list is a top-level row in its own group.
    public func grouped() -> [(group: StatusGroup, rows: [SessionListRow])] {
        let ids = Set(map(\.id))
        let newestFirst = sorted { $0.lastActivity > $1.lastActivity }
        let nested = newestFirst.filter { record in
            record.isChildSession && record.parentID.map { ids.contains($0) && $0 != record.id } == true
        }
        let nestedIDs = Set(nested.map(\.id))
        let children = Dictionary(grouping: nested) { $0.parentID ?? "" }
        let topLevel = newestFirst.filter { !nestedIDs.contains($0.id) }
        return Dictionary(grouping: topLevel) { $0.status.group }
            .sorted { $0.key < $1.key }
            .map { group, records in
                let rows = records.flatMap { parent in
                    [SessionListRow(session: parent, isNested: false)]
                        + (children[parent.id] ?? []).map { SessionListRow(session: $0, isNested: true) }
                }
                return (group, rows)
            }
    }
}

/// One row in the session list.
public struct SessionListRow: Sendable, Identifiable, Equatable {
    public var session: SessionRecord
    /// `true` for a child session shown under its parent row.
    public var isNested: Bool

    public var id: String { session.id }
}

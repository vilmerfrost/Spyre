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
    public var branch: String?
    public var status: SessionStatus
    public var waitingReason: String?
    public var lastActivity: Date
    public var parentID: String?
    /// The adapter refresh timed out. The row shows its last state with a "stale" mark.
    public var isStale: Bool
    /// A child session (`SPEC.md` 4.6, EXPERIMENTAL). With no `parentID`, the row shows "child, no parent".
    public var isChildSession: Bool

    public init(
        id: String,
        agent: AgentType,
        kind: SessionKind = .observed,
        workingDirectory: String,
        branch: String? = nil,
        status: SessionStatus,
        waitingReason: String? = nil,
        lastActivity: Date,
        parentID: String? = nil,
        isStale: Bool = false,
        isChildSession: Bool = false
    ) {
        self.id = id
        self.agent = agent
        self.kind = kind
        self.workingDirectory = workingDirectory
        self.branch = branch
        self.status = status
        self.waitingReason = waitingReason
        self.lastActivity = lastActivity
        self.parentID = parentID
        self.isStale = isStale
        self.isChildSession = isChildSession
    }

    /// The last path component of the working directory.
    public var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    /// `true` when a working session had no activity for longer than the threshold.
    public func hasNoActivityFlag(now: Date, config: SpyreConfig) -> Bool {
        status == .working && now.timeIntervalSince(lastActivity) > config.noActivityThreshold
    }
}

extension Array where Element == SessionRecord {
    /// The number shown in the menubar badge.
    public var waitingCount: Int { filter { $0.status.countsInBadge }.count }

    /// Sessions grouped by status. Inside a group, the newest activity comes first.
    public func grouped() -> [(group: StatusGroup, sessions: [SessionRecord])] {
        Dictionary(grouping: self) { $0.status.group }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.lastActivity > $1.lastActivity }) }
    }
}

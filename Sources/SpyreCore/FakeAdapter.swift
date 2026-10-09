import Foundation

/// An adapter that returns fixed sessions. For tests, previews, and the scaffold UI only.
/// All paths and IDs are fake.
public struct FakeAdapter: AgentAdapter {
    public let agent: AgentType = .claudeCode
    public let capabilities: AdapterCapabilities = .observe
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func refresh() async -> AdapterSnapshot {
        AdapterSnapshot(sessions: Self.sessions(now: now()), formatVersions: ["fake": "1"])
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    /// The fixed test sessions: two waiting, one working, one idle, one done, one unknown.
    public static func sessions(now: Date) -> [SessionRecord] {
        [
            SessionRecord(
                id: "fake-1", agent: .claudeCode, workingDirectory: "/Users/you/Projects/app",
                branch: "main", status: .waiting, waitingReason: "permission prompt",
                lastActivity: now.addingTimeInterval(-20)
            ),
            SessionRecord(
                id: "fake-2", agent: .codex, workingDirectory: "/Users/you/Projects/api",
                branch: "feat/login", status: .waiting, lastActivity: now.addingTimeInterval(-90)
            ),
            SessionRecord(
                id: "fake-3", agent: .claudeCode, workingDirectory: "/Users/you/Projects/site",
                branch: "fix/nav", status: .working, lastActivity: now.addingTimeInterval(-5)
            ),
            SessionRecord(
                id: "fake-4", agent: .claudeCode, workingDirectory: "/Users/you/Projects/app",
                status: .idle, lastActivity: now.addingTimeInterval(-600), parentID: "fake-1"
            ),
            SessionRecord(
                id: "fake-5", agent: .codex, workingDirectory: "/Users/you/Projects/cli",
                status: .done, lastActivity: now.addingTimeInterval(-300)
            ),
            SessionRecord(
                id: "fake-6", agent: .claudeCode, workingDirectory: "/Users/you/Projects/docs",
                status: .unknown, lastActivity: now.addingTimeInterval(-40), isStale: true
            ),
        ]
    }
}

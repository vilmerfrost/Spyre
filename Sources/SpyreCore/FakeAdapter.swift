import Foundation

/// An adapter that returns fixed sessions. For tests and the hidden `-SpyreDemo` launch argument only.
/// All paths, titles, and IDs are fake.
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

    /// `true` when Spyre was launched with the hidden `-SpyreDemo` argument. Spyre then shows these fake
    /// sessions instead of reading `~/.claude` and `~/.codex`. For visual checks without real data.
    public static func isRequested(arguments: [String]) -> Bool {
        arguments.contains("-SpyreDemo")
    }

    /// The fixed test sessions: two waiting, two working (one `codex exec`), one idle child, one done,
    /// and one unknown.
    public static func sessions(now: Date) -> [SessionRecord] {
        [
            SessionRecord(
                id: "fake-1", agent: .claudeCode, workingDirectory: "/Users/you/Projects/app",
                title: "Fix the login redirect", branch: "main", status: .waiting, waitingReason: "permission prompt",
                lastActivity: now.addingTimeInterval(-20)
            ),
            SessionRecord(
                id: "fake-2", agent: .codex, workingDirectory: "/Users/you/Projects/api",
                branch: "feat/login", status: .waiting, lastActivity: now.addingTimeInterval(-90)
            ),
            SessionRecord(
                id: "fake-3", agent: .claudeCode, workingDirectory: "/Users/you/Projects/site",
                title: "Tidy the navigation bar", branch: "fix/nav", status: .working,
                lastActivity: now.addingTimeInterval(-5)
            ),
            SessionRecord(
                id: "fake-4", agent: .claudeCode, workingDirectory: "/Users/you/Projects/app",
                status: .idle, lastActivity: now.addingTimeInterval(-600), parentID: "fake-1", isChildSession: true
            ),
            SessionRecord(
                id: "fake-5", agent: .codex, workingDirectory: "/Users/you/Projects/cli",
                status: .done, lastActivity: now.addingTimeInterval(-300)
            ),
            SessionRecord(
                id: "fake-6", agent: .claudeCode, workingDirectory: "/Users/you/Projects/docs",
                status: .unknown, lastActivity: now.addingTimeInterval(-40), isStale: true
            ),
            SessionRecord(
                id: "fake-7", agent: .codex, workingDirectory: "/Users/you/Projects/tools", branch: "HEAD",
                status: .working, lastActivity: now.addingTimeInterval(-12), label: "exec"
            ),
        ]
    }
}

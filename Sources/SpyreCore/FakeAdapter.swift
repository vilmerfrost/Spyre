import Foundation

/// An adapter that returns fixed sessions. For tests and the hidden `-SpyreDemo` launch argument only.
/// All paths, titles, and IDs are fake.
public struct FakeAdapter: AgentAdapter {
    public let agent: AgentType = .claudeCode
    public let capabilities: AdapterCapabilities = .observe
    private let now: @Sendable () -> Date
    private let variant: Variant

    /// The fake data sets. `-SpyreDemo` alone gives `full`. `DESIGN.md` 2.3.
    public enum Variant: String, Sendable, CaseIterable {
        /// Every row kind and group.
        case full
        /// Nothing needs you: one working session and idle sessions, some old enough to fold or hide.
        case calm
        /// No sessions.
        case empty
    }

    public init(variant: Variant = .full, now: @escaping @Sendable () -> Date = { Date() }) {
        self.variant = variant
        self.now = now
    }

    public func refresh() async -> AdapterSnapshot {
        let sessions: [SessionRecord] = switch variant {
        case .full: Self.sessions(now: now())
        case .calm: Self.calmSessions(now: now())
        case .empty: []
        }
        return AdapterSnapshot(sessions: sessions, formatVersions: ["fake": "1"])
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    /// `true` when Spyre was launched with the hidden `-SpyreDemo` argument. Spyre then shows these fake
    /// sessions instead of reading `~/.claude` and `~/.codex`. For visual checks without real data.
    public static func isRequested(arguments: [String]) -> Bool {
        arguments.contains("-SpyreDemo")
    }

    /// The data set after `-SpyreDemo`: `-SpyreDemo calm` or `-SpyreDemo empty`. Any other value gives `full`.
    public static func variant(arguments: [String]) -> Variant {
        guard let index = arguments.firstIndex(of: "-SpyreDemo"), index + 1 < arguments.count else { return .full }
        return Variant(rawValue: arguments[index + 1].lowercased()) ?? .full
    }

    /// The fixed test sessions: two waiting, two working (one `codex exec`), one idle child, three idle
    /// (one old enough to fold, one old enough to hide), one done, and one unknown.
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
            SessionRecord(
                id: "fake-8", agent: .claudeCode, workingDirectory: "/Users/you/Projects/blog",
                title: "Draft the release notes", branch: "main", status: .idle,
                lastActivity: now.addingTimeInterval(-1_500)
            ),
            SessionRecord(
                id: "fake-9", agent: .codex, workingDirectory: "/Users/you/Projects/infra",
                status: .idle, lastActivity: now.addingTimeInterval(-6 * 3_600)
            ),
            SessionRecord(
                id: "fake-10", agent: .claudeCode, workingDirectory: "/Users/you/Projects/old",
                status: .idle, lastActivity: now.addingTimeInterval(-2 * 86_400)
            ),
        ]
    }

    /// Nothing needs you: one working session, three recent idle sessions, two idle sessions old enough to
    /// fold, and one old enough to hide.
    public static func calmSessions(now: Date) -> [SessionRecord] {
        let idle: [(String, String, String?, TimeInterval)] = [
            ("calm-2", "site", "Tidy the navigation bar", 240),
            ("calm-3", "api", nil, 1_800),
            ("calm-4", "docs", "Explain the config file", 3 * 3_600),
            ("calm-5", "infra", nil, 5 * 3_600),
            ("calm-6", "cli", "Rename the flags", 9 * 3_600),
            ("calm-7", "old", nil, 30 * 3_600),
        ]
        return [
            SessionRecord(
                id: "calm-1", agent: .claudeCode, workingDirectory: "/Users/you/Projects/app",
                title: "Fix the login redirect", branch: "main", status: .working,
                lastActivity: now.addingTimeInterval(-8)
            ),
        ] + idle.enumerated().map { index, entry in
            SessionRecord(
                id: entry.0, agent: index.isMultiple(of: 2) ? .codex : .claudeCode,
                workingDirectory: "/Users/you/Projects/\(entry.1)", title: entry.2, status: .idle,
                lastActivity: now.addingTimeInterval(-entry.3)
            )
        }
    }
}

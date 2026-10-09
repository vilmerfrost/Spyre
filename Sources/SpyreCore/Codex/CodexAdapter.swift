import Foundation
import os

/// Observes Codex terminal UI (TUI) sessions. `SPEC.md` 4.5 and 5.2.
///
/// Sources: the process table (liveness, 5.2 C), the thread index (5.2 A), and rollout tails (5.2 B).
/// Lock files in `thread-writer-locks/` are not used: a shared daemon holds them, so they do not show liveness.
///
/// Known limits:
/// - Two TUIs in the same folder cannot be told apart. Spyre shows one row for that folder: the thread with the
///   newest `updated_at_ms`. The other thread in that folder is hidden. The row stays live until the last TUI
///   in the folder exits.
/// - A TUI that has no thread row yet (no first turn) is not shown.
/// - ChatGPT desktop threads have no TUI. They never show as live, only as `done` for `doneWindow` after an
///   update. `SPEC.md` 11 lists this open question.
public struct CodexAdapter: AgentAdapter {
    public let agent: AgentType = .codex
    public let capabilities: AdapterCapabilities = .observe

    /// State schema versions and CLI versions that have fixture tests.
    static let testedStateVersions: Set<String> = ["5"]
    static let testedCLIVersions: Set<String> = ["0.161.0"]

    private let codexRoot: URL
    private let processes: any CodexProcessProvider
    private let now: @Sendable () -> Date
    private let doneWindow: TimeInterval
    private let pollInterval: Duration
    private let logger = Logger(subsystem: "Spyre", category: "CodexAdapter")

    /// - Parameters:
    ///   - codexRoot: The Codex folder, normally `~/.codex`.
    ///   - doneWindow: How long a thread without a live TUI shows as `done` after its last update.
    ///   - pollInterval: How often `changes()` asks for a refresh. Process exits have no file event.
    public init(
        codexRoot: URL,
        processes: any CodexProcessProvider = SystemCodexProcessProvider(),
        now: @escaping @Sendable () -> Date = { Date() },
        doneWindow: TimeInterval = 10 * 60,
        pollInterval: Duration = .seconds(2)
    ) {
        self.codexRoot = codexRoot
        self.processes = processes
        self.now = now
        self.doneWindow = doneWindow
        self.pollInterval = max(pollInterval, .seconds(1))
    }

    public func refresh() async -> AdapterSnapshot {
        let liveFolders = Set(processes.codexProcesses().filter(\.isTerminalUI).compactMap(\.workingDirectory)
            .map(Self.normalized))
        let index = CodexThreadIndex(codexRoot: codexRoot)

        guard let database = index.latestDatabase() else {
            return unknownSnapshot(liveFolders, diagnostic: "no state_*.sqlite file found", versions: [:])
        }
        var versions = ["codex.state": String(database.version)]
        let threads: [CodexThread]
        switch index.threads(in: database.url) {
        case .success(let rows): threads = rows
        case .failure(let failure):
            return unknownSnapshot(liveFolders, diagnostic: failure.message, versions: versions)
        }

        // One thread per folder: the newest one. Two TUIs in one folder show as one session.
        var newestByFolder: [String: CodexThread] = [:]
        for thread in threads {
            let folder = Self.normalized(thread.cwd)
            if let current = newestByFolder[folder], current.updatedAt >= thread.updatedAt { continue }
            newestByFolder[folder] = thread
        }

        let reader = CodexRolloutReader()
        var sessions: [SessionRecord] = []
        var diagnostics: [AdapterDiagnostic] = []
        for (folder, thread) in newestByFolder {
            if liveFolders.contains(folder) {
                let reading = reader.read(URL(fileURLWithPath: thread.rolloutPath))
                if reading.status == .unknown {
                    diagnostics.append(AdapterDiagnostic(source: "codex.rollout", message: "rollout unreadable"))
                }
                let activity = max(thread.updatedAt, reading.lastActivity ?? thread.updatedAt)
                sessions.append(record(thread, status: reading.status, lastActivity: activity))
            } else if now().timeIntervalSince(thread.updatedAt) <= doneWindow {
                sessions.append(record(thread, status: .done, lastActivity: thread.updatedAt))
            }
        }
        // A live TUI in a folder with no thread row is not shown. See the type comment.

        let reported = Set(sessions.map(\.id))
        let cliVersions = Set(threads.filter { reported.contains($0.id) }.compactMap(\.cliVersion)).sorted()
        if !cliVersions.isEmpty { versions["codex.cli"] = cliVersions.joined(separator: ",") }
        warnAboutUntestedVersions(state: versions["codex.state"], cli: cliVersions)

        sessions.sort { ($0.lastActivity, $0.id) > ($1.lastActivity, $1.id) }
        return AdapterSnapshot(sessions: sessions, diagnostics: diagnostics, formatVersions: versions)
    }

    public func changes() -> AsyncStream<Void> {
        let interval = pollInterval
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func record(_ thread: CodexThread, status: SessionStatus, lastActivity: Date) -> SessionRecord {
        SessionRecord(
            id: thread.id, agent: .codex, workingDirectory: thread.cwd, branch: thread.gitBranch,
            status: status, lastActivity: lastActivity
        )
    }

    /// The thread index is unreadable. Each live TUI folder still shows, as `unknown`.
    private func unknownSnapshot(
        _ liveFolders: Set<String>, diagnostic: String, versions: [String: String]
    ) -> AdapterSnapshot {
        let time = now()
        let sessions = liveFolders.sorted().map { folder in
            SessionRecord(id: "codex:cwd:\(folder)", agent: .codex, workingDirectory: folder,
                          status: .unknown, lastActivity: time)
        }
        return AdapterSnapshot(
            sessions: sessions,
            diagnostics: [AdapterDiagnostic(source: "codex.state", message: diagnostic)],
            formatVersions: versions
        )
    }

    private func warnAboutUntestedVersions(state: String?, cli: [String]) {
        if let state, !Self.testedStateVersions.contains(state) {
            logger.warning("Untested Codex state schema version \(state, privacy: .public)")
        }
        for version in cli where !Self.testedCLIVersions.contains(version) {
            logger.warning("Untested Codex CLI version \(version, privacy: .public)")
        }
    }

    static func normalized(_ path: String) -> String {
        let standard = (path as NSString).standardizingPath
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}

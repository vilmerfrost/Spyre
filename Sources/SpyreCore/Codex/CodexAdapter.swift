import Foundation
import os

/// Observes Codex CLI sessions: the terminal UI (TUI) and `codex exec`. `SPEC.md` 4.5 and 5.2.
///
/// Sources: the process table (liveness, 5.2 C), the thread index (5.2 A), and rollout tails (5.2 B).
/// Lock files in `thread-writer-locks/` are not used: a shared daemon holds them, so they do not show liveness.
///
/// Known limits:
/// - Two TUIs in the same folder cannot be told apart. Spyre shows one row for that folder: the thread with the
///   newest `updated_at_ms`. The other thread in that folder is hidden. The row stays live until the last TUI
///   in the folder exits.
/// - A live TUI in a folder with no thread row shows `starting`, then `unknown` after `adapterRefreshTimeout`.
/// - ChatGPT desktop threads are out of scope. They are never shown.
public actor CodexAdapter: AgentAdapter {
    public nonisolated let agent: AgentType = .codex
    public nonisolated let capabilities: AdapterCapabilities = .observe

    /// State schema versions and CLI versions that have fixture tests.
    static let testedStateVersions: Set<String> = ["5"]
    static let testedCLIVersions: Set<String> = ["0.161.0"]
    /// `threads.originator` of ChatGPT desktop threads (verified). These threads are out of scope.
    static let desktopOriginator = "Codex Desktop"
    /// `threads.source` of a thread that `codex exec` started (verified).
    static let execSource = "exec"

    private let codexRoot: URL
    private let processes: any ProcessScanner
    private let config: SpyreConfig
    private let now: @Sendable () -> Date
    private let doneWindow: TimeInterval
    private let pollInterval: Duration
    private let logger = Logger(subsystem: "Spyre", category: "CodexAdapter")
    /// When Spyre first saw a live session folder that has no thread row. Measured with the injected clock.
    private var firstSeenWithoutThread: [String: Date] = [:]

    /// - Parameters:
    ///   - codexRoot: The Codex folder, normally `~/.codex`.
    ///   - doneWindow: How long a thread without a live TUI is reported as `done` after its last update.
    ///     The app hides `done` rows earlier, at `doneRowTimeout`.
    ///   - pollInterval: How often `changes()` asks for a refresh. Process exits have no file event.
    public init(
        codexRoot: URL,
        processes: any ProcessScanner = SystemProcessScanner(),
        config: SpyreConfig = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        doneWindow: TimeInterval = SpyreConfig.maxDoneRowTimeout,
        pollInterval: Duration = .seconds(2)
    ) {
        self.codexRoot = codexRoot
        self.processes = processes
        self.config = config
        self.now = now
        self.doneWindow = doneWindow
        self.pollInterval = max(pollInterval, .seconds(1))
    }

    /// `true` for the Codex CLI process (TUI or `codex exec`) in a terminal. `SPEC.md` 5.2 C.
    ///
    /// Decided by executable path and controlling terminal only. Spyre never reads process arguments:
    /// on macOS they come in one buffer with the environment.
    /// The `app-server-daemon` runs from its own `.../app-server-daemon/...` copy and has no terminal (verified).
    /// ChatGPT-bundled `codex` binaries live inside an `.app` bundle and have no terminal (verified).
    static func isTerminalSession(_ process: ScannedProcess) -> Bool {
        let path = process.executablePath
        return URL(fileURLWithPath: path).lastPathComponent == "codex"
            && process.hasControllingTerminal
            && !path.contains("/app-server-daemon/")
            && !path.contains(".app/Contents/")
    }

    public func refresh() async -> AdapterSnapshot {
        let time = now()
        let scanner = processes
        // Each live folder with the lowest TUI process ID in it. "Show app" starts at that process.
        var livePIDs: [String: Int32] = [:]
        for process in scanner.processes().filter(Self.isTerminalSession) {
            guard let folder = scanner.workingDirectory(of: process.pid).map(Self.normalized) else { continue }
            livePIDs[folder] = min(livePIDs[folder] ?? process.pid, process.pid)
        }
        let liveFolders = Set(livePIDs.keys)
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
        for thread in threads where thread.originator != Self.desktopOriginator {
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
                var live = record(thread, status: reading.status, lastActivity: activity)
                live.processID = livePIDs[folder]
                sessions.append(live)
            } else if time.timeIntervalSince(thread.updatedAt) <= doneWindow {
                sessions.append(record(thread, status: .done, lastActivity: thread.updatedAt))
            }
        }
        // A live session in a folder with no thread row: `starting`, then `unknown` after the refresh timeout.
        let threadless = liveFolders.subtracting(newestByFolder.keys)
        firstSeenWithoutThread = firstSeenWithoutThread.filter { threadless.contains($0.key) }
        for folder in threadless.sorted() {
            let firstSeen = firstSeenWithoutThread[folder] ?? time
            firstSeenWithoutThread[folder] = firstSeen
            let timedOut = time.timeIntervalSince(firstSeen) >= config.adapterRefreshTimeout
            var live = folderRecord(folder, status: timedOut ? .unknown : .starting, lastActivity: firstSeen)
            live.processID = livePIDs[folder]
            sessions.append(live)
        }

        let reported = Set(sessions.map(\.id))
        let cliVersions = Set(threads.filter { reported.contains($0.id) }.compactMap(\.cliVersion)).sorted()
        if !cliVersions.isEmpty { versions["codex.cli"] = cliVersions.joined(separator: ",") }
        warnAboutUntestedVersions(state: versions["codex.state"], cli: cliVersions)

        sessions.sort { ($0.lastActivity, $0.id) > ($1.lastActivity, $1.id) }
        return AdapterSnapshot(sessions: sessions, diagnostics: diagnostics, formatVersions: versions)
    }

    public nonisolated func changes() -> AsyncStream<Void> {
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
        let isExec = thread.source == Self.execSource
        return SessionRecord(
            id: thread.id, agent: .codex, workingDirectory: thread.cwd, title: thread.title,
            branch: thread.gitBranch,
            status: Self.shownStatus(status, isExec: isExec), lastActivity: lastActivity,
            label: isExec ? "exec" : nil, host: isExec ? .exec : .codex, startedAt: thread.createdAt,
            agentVersion: thread.cliVersion
        )
    }

    /// Codex has no `waiting` in the MVP (5.2 B). `codex exec` has no person at the keyboard, so it is never
    /// `waiting`, even if a later reader finds an approval event. Such a state shows as `unknown`.
    static func shownStatus(_ status: SessionStatus, isExec: Bool) -> SessionStatus {
        isExec && status == .waiting ? .unknown : status
    }

    private func folderRecord(_ folder: String, status: SessionStatus, lastActivity: Date) -> SessionRecord {
        SessionRecord(id: "codex:cwd:\(folder)", agent: .codex, workingDirectory: folder, status: status,
                      lastActivity: lastActivity, host: .codex)
    }

    /// The thread index is unreadable. Each live TUI folder still shows, as `unknown`.
    private func unknownSnapshot(
        _ liveFolders: Set<String>, diagnostic: String, versions: [String: String]
    ) -> AdapterSnapshot {
        let time = now()
        let sessions = liveFolders.sorted().map { folderRecord($0, status: .unknown, lastActivity: time) }
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

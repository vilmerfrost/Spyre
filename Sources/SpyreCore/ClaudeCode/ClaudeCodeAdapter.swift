import Foundation
import os

/// Observe-only adapter for Claude Code (`SPEC.md` 4.5, 4.6, 5.1).
///
/// Source readers: the session registry (main source), the transcript tail (branch, last activity),
/// and the process scan (liveness, PID reuse, child sessions).
/// It keeps per-session state between refreshes, so a bad registry read keeps the last known state.
public actor ClaudeCodeAdapter: AgentAdapter {
    public nonisolated let agent: AgentType = .claudeCode
    public nonisolated let capabilities: AdapterCapabilities = .observe

    /// Versions with fixture tests. Other versions log a warning.
    static let testedVersions: Set<String> = ["2.1.293", "2.1.295"]
    /// A process that started this much later than the registry `startedAt` is a reused PID.
    static let pidReuseTolerance: TimeInterval = 5
    /// How long an ended session stays in snapshots. The app hides `done` rows earlier, at `doneRowTimeout`.
    static let doneRetention = SpyreConfig.maxDoneRowTimeout
    private static let logger = Logger(subsystem: "Spyre", category: "ClaudeCodeAdapter")

    private nonisolated let sessionsDirectory: URL
    private let registry: ClaudeRegistryReader
    private let transcripts: ClaudeTranscriptReader
    private let processScanner: any ProcessScanner
    private let config: SpyreConfig
    private let now: @Sendable () -> Date

    private struct Tracked {
        var record: SessionRecord
        var firstSeen: Date
        var hadGoodRead = false
        var doneSince: Date?
    }

    /// Keyed by `r<pid>` for registry sessions and `c<pid>` for child sessions.
    private var tracked: [String: Tracked] = [:]
    private var needsRetry = false

    /// - Parameter claudeRoot: the Claude Code folder, normally `~/.claude`. Tests pass a temp folder.
    public init(
        claudeRoot: URL,
        processes: any ProcessScanner = SystemProcessScanner(),
        config: SpyreConfig = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        sessionsDirectory = claudeRoot.appendingPathComponent("sessions", isDirectory: true)
        registry = ClaudeRegistryReader(sessionsDirectory: sessionsDirectory)
        transcripts = ClaudeTranscriptReader(
            projectsDirectory: claudeRoot.appendingPathComponent("projects", isDirectory: true)
        )
        self.processScanner = processes
        self.config = config
        self.now = now
    }

    public func refresh() async -> AdapterSnapshot {
        let time = now()
        let processes = processScanner.processes()
        let byPID = Dictionary(processes.map { ($0.pid, $0) }) { first, _ in first }
        let reads = registry.read().sorted { $0.pid < $1.pid }
        var diagnostics: [AdapterDiagnostic] = []
        var seen = Set<String>()
        needsRetry = false

        for read in reads {
            let key = "r\(read.pid)"
            seen.insert(key)
            let alive = processScanner.isAlive(read.pid) && !Self.isReused(read.entry, process: byPID[read.pid])
            var item = tracked[key] ?? Tracked(record: placeholder(pid: read.pid, now: time), firstSeen: time)
            if alive, item.doneSince != nil {
                item = Tracked(record: placeholder(pid: read.pid, now: time), firstSeen: time)
            }
            if !read.isGood, alive {
                needsRetry = true
                diagnostics.append(AdapterDiagnostic(
                    source: "claude.registry", message: "\(read.pid).json has no readable status; kept last state"
                ))
            }
            apply(read, to: &item, now: time)
            if !alive {
                let firstSight = tracked[key] == nil
                if item.doneSince == nil {
                    item.doneSince = firstSight ? (read.entry?.lastActivity ?? read.modified ?? time) : time
                }
                item.record.status = .done
                item.record.waitingReason = nil
            }
            tracked[key] = item
        }

        // A new process can run before it writes its registry file. Its child row was not a real child: drop it.
        for read in reads { tracked["c\(read.pid)"] = nil }
        diagnostics += scanChildSessions(processes: processes, byPID: byPID, reads: reads, now: time, seen: &seen)

        for (key, item) in tracked where !seen.contains(key) && item.doneSince == nil {
            tracked[key]?.doneSince = time
            tracked[key]?.record.status = .done
            tracked[key]?.record.waitingReason = nil
        }
        tracked = tracked.filter { _, item in
            item.doneSince.map { time.timeIntervalSince($0) <= Self.doneRetention } ?? true
        }

        let version = reads.compactMap(\.entry)
            .max { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }?.version
        if let version, !Self.testedVersions.contains(version) {
            Self.logger.warning("Claude Code registry version \(version, privacy: .public) has no fixture tests")
        }
        return AdapterSnapshot(
            sessions: tracked.values.map(\.record).sorted { $0.id < $1.id },
            diagnostics: diagnostics,
            formatVersions: version.map { ["claude.registry": $0] } ?? [:]
        )
    }

    /// Emits on folder events in `sessions/`, every second for in-place writes,
    /// and after 250 ms when the last refresh had a bad read (`SPEC.md` 4.5).
    public nonisolated func changes() -> AsyncStream<Void> {
        let directory = sessionsDirectory
        return AsyncStream { continuation in
            let descriptor = open(directory.path, O_EVTONLY)
            let source: (any DispatchSourceFileSystemObject)? = descriptor < 0 ? nil :
                DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .global()
                )
            source?.setEventHandler { continuation.yield() }
            source?.setCancelHandler { close(descriptor) }
            source?.resume()
            let timer = Task { [weak self] in
                while !Task.isCancelled {
                    let retry = await self?.needsRetry ?? false
                    try? await Task.sleep(for: retry ? .milliseconds(250) : .seconds(1))
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in
                source?.cancel()
                timer.cancel()
            }
        }
    }

    // MARK: - Registry

    private func placeholder(pid: Int32, now: Date) -> SessionRecord {
        SessionRecord(id: "claude-pid-\(pid)", agent: .claudeCode, workingDirectory: "", status: .starting,
                      lastActivity: now, processID: pid)
    }

    /// `SPEC.md` 4.5 gap rules. Metadata comes from any parsed file. Status comes only from a good read.
    private func apply(_ read: ClaudeRegistryRead, to item: inout Tracked, now: Date) {
        if let entry = read.entry {
            if let id = entry.sessionId { item.record.id = id }
            if let cwd = entry.cwd { item.record.workingDirectory = cwd }
            if let name = entry.name { item.record.title = name }
            if let host = SessionHost(claudeEntrypoint: entry.entrypoint) { item.record.host = host }
            if let started = entry.startedAt { item.record.startedAt = Date(timeIntervalSince1970: started / 1000) }
            if let date = entry.lastActivity { item.record.lastActivity = date }
            if let cwd = entry.cwd, let id = entry.sessionId,
               let summary = transcripts.summary(cwd: cwd, sessionID: id) {
                item.record.branch = summary.branch ?? item.record.branch
                if let date = summary.lastActivity { item.record.lastActivity = max(item.record.lastActivity, date) }
            }
        }
        if read.isGood, let entry = read.entry, let status = entry.mappedStatus {
            item.hadGoodRead = true
            item.record.status = status
            item.record.waitingReason = status == .waiting ? entry.waitingFor : nil
        } else if !item.hadGoodRead {
            let timedOut = now.timeIntervalSince(item.firstSeen) >= config.adapterRefreshTimeout
            item.record.status = timedOut ? .unknown : .starting
        }
    }

    /// `SPEC.md` 5.1 A: a live PID whose process started after the registry session is a reused PID.
    static func isReused(_ entry: ClaudeRegistryEntry?, process: ScannedProcess?) -> Bool {
        guard let start = process?.startTime, let entry else { return false }
        let registered = entry.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? entry.procStartDate
        guard let registered else { return false }
        return start.timeIntervalSince(registered) > pidReuseTolerance
    }

    /// `SPEC.md` 5.1 D: match on the executable path, never on the process name.
    static func isClaudeCode(_ executablePath: String) -> Bool {
        if executablePath.hasSuffix("/claude") { return true }
        guard let range = executablePath.range(of: "/.local/share/claude/versions/") else { return false }
        let version = executablePath[range.upperBound...]
        return !version.isEmpty && !version.contains("/")
    }

    // MARK: - Child sessions (EXPERIMENTAL, SPEC.md 4.6)

    /// EXPERIMENTAL. A live Claude Code process with no registry file is a child session.
    /// The parent is the first process up the parent-PID chain that has a registry file.
    /// Status comes from the transcript tail. Two children in one folder can be matched to the wrong transcript.
    private func scanChildSessions(
        processes: [ScannedProcess], byPID: [Int32: ScannedProcess], reads: [ClaudeRegistryRead], now: Date,
        seen: inout Set<String>
    ) -> [AdapterDiagnostic] {
        let registryPIDs = Set(reads.map(\.pid))
        var claimed = Set(reads.compactMap(\.entry?.sessionId))
        var diagnostics: [AdapterDiagnostic] = []
        // A process that had a registry file is never a child: on exit it deletes the file before it ends.
        let children = processes.filter {
            Self.isClaudeCode($0.executablePath) && !registryPIDs.contains($0.pid) && tracked["r\($0.pid)"] == nil
        }
            .sorted { $0.pid < $1.pid }

        for process in children {
            let key = "c\(process.pid)"
            var record = SessionRecord(
                id: "claude-child-\(process.pid)", agent: .claudeCode, workingDirectory: "", status: .unknown,
                lastActivity: process.startTime ?? now, isChildSession: true, processID: process.pid,
                startedAt: process.startTime
            )
            record.parentID = parentRecordID(of: process, byPID: byPID, registryPIDs: registryPIDs)
            let cwd = processScanner.workingDirectory(of: process.pid)
            if let cwd {
                // A readable folder with no unclaimed transcript is not shown. Desktop-app helper processes
                // without a registry file or transcript were observed; they are not sessions.
                guard let found = transcripts.newestTranscript(cwd: cwd, excluding: claimed) else {
                    diagnostics.append(AdapterDiagnostic(
                        source: "claude.child", message: "process \(process.pid) has no transcript; not shown"
                    ))
                    continue
                }
                claimed.insert(found.sessionID)
                record.workingDirectory = cwd
                if let summary = transcripts.summary(of: found.url) {
                    record.branch = summary.branch
                    record.lastActivity = summary.lastActivity ?? record.lastActivity
                    record.status = summary.status ?? .unknown
                }
            }
            if record.status == .unknown {
                diagnostics.append(AdapterDiagnostic(
                    source: "claude.child", message: "child process \(process.pid) has no readable data"
                ))
            }
            seen.insert(key)
            let firstSeen = tracked[key].flatMap { $0.doneSince == nil ? $0.firstSeen : nil } ?? now
            tracked[key] = Tracked(record: record, firstSeen: firstSeen, hadGoodRead: record.status != .unknown)
        }
        return diagnostics
    }

    private func parentRecordID(of process: ScannedProcess, byPID: [Int32: ScannedProcess],
                                registryPIDs: Set<Int32>) -> String? {
        var pid = process.parentPID
        for _ in 0..<32 {
            guard pid > 1 else { return nil }
            if registryPIDs.contains(pid), let parent = tracked["r\(pid)"], parent.doneSince == nil {
                return parent.record.id
            }
            guard let next = byPID[pid]?.parentPID else { return nil }
            pid = next
        }
        return nil
    }
}

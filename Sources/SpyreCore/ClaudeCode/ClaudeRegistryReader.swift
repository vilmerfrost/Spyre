import Foundation

/// The fields Spyre uses from `~/.claude/sessions/<pid>.json` (`SPEC.md` 5.1 A). All optional.
struct ClaudeRegistryEntry: Decodable, Sendable, Equatable {
    var pid: Int32?
    var sessionId: String?
    var cwd: String?
    /// The session title. Shown locally only. Never logged.
    var name: String?
    var startedAt: Double?
    var procStart: String?
    var version: String?
    var status: String?
    var waitingFor: String?
    var updatedAt: Double?
    var statusUpdatedAt: Double?

    /// The newest registry timestamp, from ms epoch.
    var lastActivity: Date? {
        [updatedAt, statusUpdatedAt].compactMap { $0 }.max().map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// `SPEC.md` 5.1 A mapping. `nil` when the file has no status (a bad read).
    var mappedStatus: SessionStatus? {
        switch status {
        case nil: nil
        case "busy": .working
        case "waiting": .waiting
        case "idle": .idle
        default: .unknown
        }
    }

    /// `procStart` as written by 2.1.29x, for example `Fri Oct  9 14:16:29 2026`, in UTC (verified on one Mac).
    /// Older versions wrote a number. Those give `nil`.
    var procStartDate: Date? {
        guard let procStart else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        let collapsed = procStart.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return formatter.date(from: collapsed)
    }
}

/// The result of reading one registry file.
struct ClaudeRegistryRead: Sendable {
    var pid: Int32
    /// `nil` when the file did not parse.
    var entry: ClaudeRegistryEntry?
    var modified: Date?

    /// `SPEC.md` 4.5: a good read parses and has a `status`.
    var isGood: Bool { entry?.status != nil }
}

/// Reads the session registry folder. Opens only `<pid>.json` files. Never opens `.key` files.
struct ClaudeRegistryReader: Sendable {
    let sessionsDirectory: URL

    func read() -> [ClaudeRegistryRead] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.compactMap { url in
            guard url.pathExtension == "json", let pid = Int32(url.deletingPathExtension().lastPathComponent) else {
                return nil
            }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let entry = (try? Data(contentsOf: url)).flatMap {
                try? JSONDecoder().decode(ClaudeRegistryEntry.self, from: $0)
            }
            return ClaudeRegistryRead(pid: pid, entry: entry, modified: modified)
        }
    }
}

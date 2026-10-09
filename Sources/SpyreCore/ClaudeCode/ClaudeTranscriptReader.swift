import Foundation

/// What Spyre takes from the tail of one transcript. Never holds message content.
struct ClaudeTranscriptSummary: Sendable, Equatable {
    var branch: String?
    var lastActivity: Date?
    /// EXPERIMENTAL (`SPEC.md` 4.6): status from turn records. `nil` when the tail has no turn record.
    var status: SessionStatus?
}

/// Reads the tail of `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` (`SPEC.md` 5.1 C).
struct ClaudeTranscriptReader: Sendable {
    let projectsDirectory: URL
    var tailBytes = 256 * 1024

    /// Each character that is not a letter, digit, or `-` becomes `-`. Observed for `/` and `.` (inferred for others).
    static func encodedFolderName(for cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") ? $0 : "-" })
    }

    func folder(for cwd: String) -> URL {
        projectsDirectory.appendingPathComponent(Self.encodedFolderName(for: cwd), isDirectory: true)
    }

    func summary(cwd: String, sessionID: String) -> ClaudeTranscriptSummary? {
        summary(of: folder(for: cwd).appendingPathComponent("\(sessionID).jsonl"))
    }

    /// EXPERIMENTAL (`SPEC.md` 4.6): the newest transcript in the folder whose session ID is not excluded.
    func newestTranscript(cwd: String, excluding: Set<String>) -> (sessionID: String, url: URL)? {
        let key = URLResourceKey.contentModificationDateKey
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder(for: cwd), includingPropertiesForKeys: [key]
        )) ?? []
        let candidates = files.filter {
            $0.pathExtension == "jsonl" && !excluding.contains($0.deletingPathExtension().lastPathComponent)
        }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
        }
        let newest = candidates.max { (modified($0), $1.path) < (modified($1), $0.path) }
        return newest.map { ($0.deletingPathExtension().lastPathComponent, $0) }
    }

    /// Reads only the last `tailBytes` bytes. Skips lines that do not parse, such as a truncated last line.
    func summary(of url: URL) -> ClaudeTranscriptSummary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if offset > 0, !lines.isEmpty { lines.removeFirst() }

        var summary = ClaudeTranscriptSummary()
        let decoder = JSONDecoder()
        for line in lines {
            guard let record = try? decoder.decode(TranscriptLine.self, from: Data(line)) else { continue }
            if let branch = record.gitBranch { summary.branch = branch }
            if let date = record.timestamp.flatMap(Self.parseTimestamp) {
                summary.lastActivity = max(summary.lastActivity ?? date, date)
            }
            if let status = record.turnStatus { summary.status = status }
        }
        return summary
    }

    static func parseTimestamp(_ text: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? fractional.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

/// The fields Spyre reads from one transcript line. `message.stop_reason` is metadata, not content.
private struct TranscriptLine: Decodable {
    var type: String?
    var subtype: String?
    var timestamp: String?
    var gitBranch: String?
    var stopReason: String?

    private enum CodingKeys: String, CodingKey { case type, subtype, timestamp, gitBranch, message }
    private enum MessageKeys: String, CodingKey { case stopReason = "stop_reason" }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        subtype = try? container.decodeIfPresent(String.self, forKey: .subtype)
        timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
        gitBranch = try? container.decodeIfPresent(String.self, forKey: .gitBranch)
        let message = try? container.nestedContainer(keyedBy: MessageKeys.self, forKey: .message)
        stopReason = try? message?.decodeIfPresent(String.self, forKey: .stopReason)
    }

    /// EXPERIMENTAL (`SPEC.md` 4.6): a turn end gives `idle`. A newer user or assistant record gives `working`.
    var turnStatus: SessionStatus? {
        switch type {
        case "assistant": stopReason == "end_turn" ? .idle : .working
        case "user": .working
        case "system" where subtype == "turn_duration" || subtype == "stop_hook_summary": .idle
        default: nil
        }
    }
}

import Foundation

/// Reads the status of one live thread from the tail of its rollout file. `SPEC.md` 5.2 B.
///
/// Decodes only `type`, `timestamp`, and `payload.type`. Never decodes message content.
struct CodexRolloutReader: Sendable {
    /// The tail sizes to try, in bytes. A larger tail is read only when the smaller one had no status event.
    var tailSizes: [Int] = [64 * 1024, 1024 * 1024]

    struct Reading: Sendable, Equatable {
        var status: SessionStatus
        var lastActivity: Date?
    }

    /// The status of a live session. Gives `unknown` when the file cannot be read or parsed.
    func read(_ url: URL) -> Reading {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Reading(status: .unknown) }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return Reading(status: .unknown) }

        for tail in tailSizes {
            let start = size > UInt64(tail) ? size - UInt64(tail) : 0
            guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else {
                return Reading(status: .unknown)
            }
            var lines = data.split(separator: UInt8(ascii: "\n"))
            // The first line of a partial tail is cut. Drop it.
            if start > 0, !lines.isEmpty { lines.removeFirst() }
            if let reading = Self.status(lines: lines, readWholeFile: start == 0) { return reading }
            if start == 0 { break }
        }
        return Reading(status: .unknown)
    }

    /// The newest status event wins. `nil` means "read more of the file".
    static func status(lines: [Data.SubSequence], readWholeFile: Bool) -> Reading? {
        let decoder = JSONDecoder()
        var parsedAny = false
        var newestTime: Date?
        for line in lines.reversed() {
            guard let record = try? decoder.decode(Record.self, from: Data(line)) else { continue }
            parsedAny = true
            let time = record.timestamp.flatMap { try? Date($0, strategy: .iso8601WithFractions) }
            newestTime = newestTime ?? time
            guard record.type == "event_msg" else { continue }
            switch record.payloadType {
            case "task_started": return Reading(status: .working, lastActivity: newestTime)
            case "task_complete", "turn_aborted": return Reading(status: .idle, lastActivity: newestTime)
            default: continue
            }
        }
        guard readWholeFile else { return nil }
        // A live TUI with valid records but no turn yet is not running a turn.
        return parsedAny ? Reading(status: .idle, lastActivity: newestTime) : Reading(status: .unknown)
    }

    private struct Record: Decodable {
        var type: String?
        var timestamp: String?
        var payloadType: String?

        private enum Keys: String, CodingKey { case type, timestamp, payload }
        private struct Payload: Decodable { var type: String? }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            type = try? container.decodeIfPresent(String.self, forKey: .type)
            timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
            payloadType = (try? container.decodeIfPresent(Payload.self, forKey: .payload))?.type
        }
    }
}

private extension ParseStrategy where Self == Date.ISO8601FormatStyle {
    static var iso8601WithFractions: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    }
}

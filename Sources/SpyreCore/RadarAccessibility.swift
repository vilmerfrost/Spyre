import Foundation

/// The VoiceOver texts of the Radar list. `SPEC.md` 4.2.
public enum RadarSpeech {
    /// The status word of a row.
    public static func statusWord(_ status: SessionStatus) -> String {
        switch status {
        case .waiting: "Needs you"
        case .working: "Working"
        case .starting: "Starting"
        case .idle: "Idle"
        case .unknown: "Unknown"
        case .done: "Done"
        }
    }

    /// A time span in words, for example "20 seconds", "1 minute", "3 hours".
    public static func duration(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let (value, unit): (Int, String) = switch seconds {
        case ..<60: (seconds, "second")
        case ..<3_600: (seconds / 60, "minute")
        case ..<86_400: (seconds / 3_600, "hour")
        default: (seconds / 86_400, "day")
        }
        return "\(value) \(unit)\(value == 1 ? "" : "s")"
    }

    /// "{Title}. {Status}. {Waiting reason}. {Project}, {branch}, {agent}. Last activity {time} ago."
    /// A nested child adds "Child session of {parent}.", a flagged row "No activity for {time}.",
    /// and a stale row "Stale.". Empty parts are left out.
    public static func rowLabel(
        _ record: SessionRecord, text: SessionRowText, parentTitle: String?, hasNoActivityFlag: Bool, now: Date
    ) -> String {
        // Like line 2: the project is left out when the title already is the project name.
        let project = text.project == text.title ? nil : text.project
        let place = [project, text.branch, text.agent].compactMap { $0 }.joined(separator: ", ")
        let time = duration(from: record.lastActivity, to: now)
        let parts: [String?] = [
            text.title,
            statusWord(record.status),
            record.waitingText,
            place,
            parentTitle.map { "Child session of \($0)" },
            hasNoActivityFlag ? "No activity for \(time)" : nil,
            record.isStale ? "Stale" : nil,
            "Last activity \(time) ago",
        ]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.map { $0.hasSuffix(".") ? $0 : $0 + "." }
            .joined(separator: " ")
    }

    /// The label of a disclosure header, for example "Idle, 2 sessions".
    public static func disclosureLabel(_ title: String, count: Int) -> String {
        "\(title), \(count) session\(count == 1 ? "" : "s")"
    }
}

/// Decides the VoiceOver announcements for sessions that need you. `SPEC.md` 4.1.
///
/// A session is announced once, when it has been `waiting` for `alertDelay`. At most one announcement per
/// `spacing` seconds. Sessions that become due while one is held back are announced together:
/// "{N} sessions need you." Working, idle, and done are never announced. The clock is injected.
public struct NeedsYouAnnouncer: Sendable {
    public var alertDelay: TimeInterval
    public var spacing: TimeInterval
    private var waitingSince: [String: Date] = [:]
    private var announced: Set<String> = []
    private var lastAnnouncement: Date?

    public init(alertDelay: TimeInterval, spacing: TimeInterval = 5) {
        self.alertDelay = alertDelay
        self.spacing = spacing
    }

    /// Feeds the current sessions. Returns the text to announce now, or `nil`.
    /// - Parameter title: the row title of a session.
    public mutating func update(
        _ sessions: [SessionRecord], now: Date, title: (SessionRecord) -> String
    ) -> String? {
        let waiting = sessions.filter { $0.status == .waiting }
        let ids = Set(waiting.map(\.id))
        waitingSince = waitingSince.filter { ids.contains($0.key) }
        announced.formIntersection(ids)
        for record in waiting where waitingSince[record.id] == nil { waitingSince[record.id] = now }
        let due = waiting.filter { record in
            !announced.contains(record.id)
                && now.timeIntervalSince(waitingSince[record.id] ?? now) >= alertDelay
        }
        guard !due.isEmpty else { return nil }
        if let last = lastAnnouncement, now.timeIntervalSince(last) < spacing { return nil }
        lastAnnouncement = now
        announced.formUnion(due.map(\.id))
        guard due.count == 1, let record = due.first else { return "\(due.count) sessions need you." }
        return "\(title(record)) needs you. \(record.waitingText ?? "Needs input")."
    }
}

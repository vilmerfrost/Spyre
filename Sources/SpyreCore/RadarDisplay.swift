import CoreGraphics
import Foundation

/// What the count line says. `SPEC.md` 4.2.
public enum CountLineContent: Sendable, Equatable {
    /// At least one session needs you: the big count line, "2 needs you 1 working 3 idle".
    case attention(SessionCounts)
    /// Nothing needs you: "Nothing needs you." and a short summary, for example "1 working · 7 idle".
    /// The summary leaves out zero parts. It is empty when nothing works and nothing is idle.
    case calm(summary: String)

    public init(_ counts: SessionCounts) {
        if counts.needsYou > 0 {
            self = .attention(counts)
        } else {
            let parts = [(counts.working, "working"), (counts.idle, "idle")]
                .filter { $0.0 > 0 }
                .map { "\($0.0) \($0.1)" }
            self = .calm(summary: parts.joined(separator: " · "))
        }
    }

    /// The text of the calm line.
    public static let calmTitle = "Nothing needs you."

    /// One VoiceOver label for the whole line.
    public var accessibilityLabel: String {
        switch self {
        case .attention(let counts):
            "\(counts.needsYou) need you, \(counts.working) working, \(counts.idle) idle"
        case .calm(let summary):
            summary.isEmpty
                ? Self.calmTitle : "\(Self.calmTitle) \(summary.replacingOccurrences(of: " · ", with: ", "))"
        }
    }
}

/// The empty state of the Radar section and the menubar window. `SPEC.md` 4.2.
public enum EmptyRadar {
    public static let title = "Nothing running."
    public static let body = "Start Claude Code or Codex in a terminal. Spyre shows it here within a few seconds."
}

/// The menubar label text. `SPEC.md` 4.1.
public enum MenuBarBadge {
    /// `nil` at 0 (icon only), "1" to "9", then "9+".
    public static func text(waitingCount: Int) -> String? {
        switch waitingCount {
        case ..<1: nil
        case 1...9: "\(waitingCount)"
        default: "9+"
        }
    }

    /// The VoiceOver label: "Spyre" or "Spyre, 2 waiting".
    public static func accessibilityLabel(waitingCount: Int) -> String {
        waitingCount > 0 ? "Spyre, \(waitingCount) waiting" : "Spyre"
    }
}

/// The rows of the menubar window: Needs you, then Working, at most `limit`, and how many more Spyre has.
public struct MenuPanelContent: Sendable {
    public var rows: [(group: StatusGroup, row: SessionListRow)]
    /// The visible sessions the menubar window leaves out. The "N more in Spyre" button shows it.
    public var moreCount: Int

    public init(_ sessions: [SessionRecord], limit: Int) {
        rows = sessions.menuRows(limit: limit)
        moreCount = max(0, sessions.count - rows.count)
    }

    /// "3 more in Spyre", or `nil` when nothing is left out.
    public var moreText: String? { moreCount > 0 ? "\(moreCount) more in Spyre" : nil }
}

/// Size rules for the main window. `DESIGN.md` 2.5.
public enum WindowFrameRule {
    /// The window frame that fits `contentHeight`, clamped to `minHeight...maxHeight` and to the screen.
    /// The top edge stays where it is, so the window grows and shrinks downward.
    /// - Parameters:
    ///   - frame: the current window frame, in screen coordinates (origin at the bottom left).
    ///   - contentHeight: the height the content needs, title bar included.
    ///   - visible: the visible frame of the screen the window is on.
    public static func fitted(
        _ frame: CGRect, contentHeight: CGFloat, minHeight: CGFloat, maxHeight: CGFloat, visible: CGRect
    ) -> CGRect {
        let limit = min(maxHeight, visible.height)
        let height = max(min(minHeight, limit), min(contentHeight.rounded(.up), limit))
        var result = frame
        result.origin.y = frame.maxY - height
        result.size.height = height
        if result.minY < visible.minY { result.origin.y = visible.minY }
        return result
    }

    /// A restored frame that is fully reachable: it is moved onto the screen it overlaps most and made to fit.
    /// A frame that is on no screen is centered on the first screen.
    /// - Parameter screens: the visible frames of all screens. The first is the main screen.
    public static func clamped(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let main = screens.first else { return frame }
        let best = screens.max { overlap(frame, $0) < overlap(frame, $1) } ?? main
        var result = frame
        result.size.width = min(frame.width, best.width)
        result.size.height = min(frame.height, best.height)
        if overlap(frame, best) == 0 {
            result.origin.x = main.midX - result.width / 2
            result.origin.y = main.midY - result.height / 2
            return result
        }
        result.origin.x = min(max(frame.minX, best.minX), best.maxX - result.width)
        result.origin.y = min(max(frame.minY, best.minY), best.maxY - result.height)
        return result
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let area = a.intersection(b)
        return area.isNull ? 0 : area.width * area.height
    }
}

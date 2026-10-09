import CoreGraphics
import Foundation
import Testing
@testable import SpyreCore

// All paths are fake.

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func record(_ id: String, _ status: SessionStatus, ageSeconds: TimeInterval = 0) -> SessionRecord {
    SessionRecord(
        id: id, agent: .claudeCode, workingDirectory: "/Users/you/Projects/\(id)", status: status,
        lastActivity: now.addingTimeInterval(-ageSeconds)
    )
}

@Suite(.timeLimit(.minutes(1)))
struct RadarDisplayTests {
    // MARK: Count line (SPEC 4.2)

    @Test func countLineShowsNumbersWhenSomethingNeedsYou() {
        let counts = SessionCounts([record("w", .waiting), record("k", .working)])
        #expect(CountLineContent(counts) == .attention(counts))
        #expect(CountLineContent(counts).accessibilityLabel == "1 need you, 1 working, 0 idle")
    }

    @Test func zeroLineSaysNothingNeedsYouAndLeavesOutZeroParts() {
        let mixed = SessionCounts([record("k", .working)] + (1...7).map { record("i\($0)", .idle) })
        #expect(CountLineContent(mixed) == .calm(summary: "1 working · 7 idle"))
        #expect(CountLineContent(mixed).accessibilityLabel == "Nothing needs you. 1 working, 7 idle")
        #expect(CountLineContent(SessionCounts([record("i", .idle)])) == .calm(summary: "1 idle"))
        #expect(CountLineContent(SessionCounts([record("k", .working)])) == .calm(summary: "1 working"))
        let none = CountLineContent(SessionCounts([record("d", .done)]))
        #expect(none == .calm(summary: ""))
        #expect(none.accessibilityLabel == "Nothing needs you.")
    }

    @Test func emptyStateText() {
        #expect(EmptyRadar.title == "Nothing running.")
        #expect(EmptyRadar.body.hasPrefix("Start Claude Code or Codex in a terminal."))
    }

    // MARK: Idle fold and hide (SPEC 4.2)

    @Test func veryOldIdleSessionsAreHidden() {
        let config = SpyreConfig(idleHideAfter: 86_400)
        let sessions = [
            record("new", .idle, ageSeconds: 60), record("edge", .idle, ageSeconds: 86_400),
            record("old", .idle, ageSeconds: 86_401), record("oldWorking", .working, ageSeconds: 200_000),
        ]
        #expect(sessions.visible(now: now, config: config).map(\.id) == ["new", "edge", "oldWorking"])
        #expect([record("old", .idle, ageSeconds: 90_000)].visible(now: now, config: config).isEmpty)
    }

    @Test func oldIdleRowsFoldIntoEarlier() throws {
        let sessions = [
            record("recent", .idle, ageSeconds: 600), record("edge", .idle, ageSeconds: 14_400),
            record("old", .idle, ageSeconds: 14_401), record("older", .idle, ageSeconds: 50_000),
            record("busy", .working, ageSeconds: 50_000),
        ]
        let fold = IdleFold(now: now, after: 14_400)
        let sections = sessions.sections(expanded: [.idle], idleFold: fold)
        let idle = try #require(sections.first { $0.group == .idle })
        #expect(idle.rows.map(\.id) == ["recent", "edge"])
        #expect(idle.earlierRows.map(\.id) == ["old", "older"])
        #expect(idle.count == 4)
        #expect(idle.earlierCount == 2)
        #expect(idle.showsEarlier)
        #expect(idle.visibleEarlierRows.isEmpty)
        #expect(sections.first { $0.group == .working }?.earlierRows.isEmpty == true)

        let open = sessions.sections(expanded: [.idle], idleFold: IdleFold(now: now, after: 14_400, isExpanded: true))
        #expect(open.first { $0.group == .idle }?.visibleEarlierRows.map(\.id) == ["old", "older"])
        let folded = sessions.sections(idleFold: IdleFold(now: now, after: 14_400, isExpanded: true))
        #expect(folded.first { $0.group == .idle }?.showsEarlier == false)
        #expect(folded.first { $0.group == .idle }?.visibleEarlierRows.isEmpty == true)
    }

    @Test func nestedChildMovesIntoEarlierWithItsParent() throws {
        var kid = record("kid", .idle, ageSeconds: 10)
        kid.isChildSession = true
        kid.parentID = "parent"
        let sections = [record("parent", .idle, ageSeconds: 20_000), kid]
            .sections(expanded: [.idle], idleFold: IdleFold(now: now, after: 14_400))
        let idle = try #require(sections.first { $0.group == .idle })
        #expect(idle.rows.isEmpty)
        #expect(idle.earlierRows.map(\.id) == ["parent", "kid"])
        #expect(idle.earlierCount == 1)
    }

    // MARK: Menubar (SPEC 4.1, 4.2)

    @Test(arguments: [(0, nil), (1, "1"), (9, "9"), (10, "9+"), (250, "9+")] as [(Int, String?)])
    func menuBarLabelText(count: Int, text: String?) {
        #expect(MenuBarBadge.text(waitingCount: count) == text)
    }

    @Test func menuBarAccessibilityLabel() {
        #expect(MenuBarBadge.accessibilityLabel(waitingCount: 0) == "Spyre")
        #expect(MenuBarBadge.accessibilityLabel(waitingCount: 2) == "Spyre, 2 waiting")
    }

    @Test func menuPanelShowsAtMostFiveRowsAndHowManyMore() {
        let sessions = (1...4).map { record("w\($0)", .waiting) } + (1...3).map { record("k\($0)", .working) }
            + [record("i", .idle)]
        let panel = MenuPanelContent(sessions, limit: 5)
        #expect(panel.rows.count == 5)
        #expect(panel.rows.prefix(4).allSatisfy { $0.group == .waiting })
        #expect(panel.moreCount == 3)
        #expect(panel.moreText == "3 more in Spyre")
        let few = MenuPanelContent([record("w", .waiting)], limit: 5)
        #expect(few.moreCount == 0)
        #expect(few.moreText == nil)
    }

    // MARK: Window frame (DESIGN 2.5)

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func windowHeightFitsContentWithinLimitsAndKeepsTopEdge() {
        let frame = CGRect(x: 100, y: 200, width: 880, height: 440)
        let grown = WindowFrameRule.fitted(frame, contentHeight: 520.4, minHeight: 440, maxHeight: 640, visible: screen)
        #expect(grown.height == 521)
        #expect(grown.maxY == frame.maxY)
        #expect(grown.width == 880)
        let small = WindowFrameRule.fitted(frame, contentHeight: 120, minHeight: 440, maxHeight: 640, visible: screen)
        #expect(small.height == 440)
        let big = WindowFrameRule.fitted(frame, contentHeight: 2_000, minHeight: 440, maxHeight: 640, visible: screen)
        #expect(big.height == 640)
        #expect(big.maxY == frame.maxY)
    }

    @Test func fittedWindowStaysOnTheScreen() {
        let low = CGRect(x: 100, y: 20, width: 880, height: 440)
        let fitted = WindowFrameRule.fitted(low, contentHeight: 640, minHeight: 440, maxHeight: 640, visible: screen)
        #expect(fitted.minY == screen.minY)
        #expect(fitted.height == 640)
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 300)
        #expect(WindowFrameRule.fitted(tiny, contentHeight: 600, minHeight: 440, maxHeight: 640, visible: tiny).height
            == 300)
    }

    @Test func restoredFrameIsClampedToAScreen() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let screens = [screen, second]
        let inside = CGRect(x: 200, y: 200, width: 880, height: 500)
        #expect(WindowFrameRule.clamped(inside, screens: screens) == inside)
        let halfOff = CGRect(x: 1000, y: 100, width: 880, height: 500)
        let moved = WindowFrameRule.clamped(halfOff, screens: [screen])
        #expect(moved.maxX == screen.maxX)
        #expect(moved.size == halfOff.size)
        let gone = CGRect(x: 9_000, y: 9_000, width: 880, height: 500)
        let centered = WindowFrameRule.clamped(gone, screens: screens)
        #expect(centered.midX == screen.midX)
        #expect(centered.midY == screen.midY)
        let onSecond = CGRect(x: 3_200, y: 100, width: 880, height: 500)
        #expect(WindowFrameRule.clamped(onSecond, screens: screens).maxX == second.maxX)
    }
}

import Foundation
import Testing
@testable import SpyreCore

// All paths and titles are fake.

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func record(
    _ id: String, _ status: SessionStatus, title: String? = nil, age: TimeInterval = 0, parent: String? = nil
) -> SessionRecord {
    SessionRecord(
        id: id, agent: .claudeCode, workingDirectory: "/Users/you/Projects/\(id)", title: title, status: status,
        lastActivity: now.addingTimeInterval(-age), parentID: parent, isChildSession: parent != nil
    )
}

@Suite(.timeLimit(.minutes(1)))
struct RadarAccessibilityTests {
    // MARK: Keyboard model (SPEC 4.2)

    private var sections: [SessionSection] {
        let sessions = [
            record("w", .waiting), record("kid", .idle, parent: "w"), record("k", .working),
            record("i", .idle, age: 60), record("old", .idle, age: 20_000),
        ]
        return sessions.sections(expanded: [.idle], idleFold: IdleFold(now: now, after: 14_400))
    }

    @Test func entriesFollowScreenOrder() {
        let navigation = RadarNavigation(sections: sections)
        #expect(navigation.entries.map(\.item) == [
            .header(.waiting), .row("w"), .row("kid"), .header(.working), .row("k"), .header(.idle), .row("i"),
            .earlier,
        ])
        #expect(navigation.entries[0].isExpanded == nil)
        #expect(navigation.entries[5].isExpanded == true)
        #expect(navigation.entries[7].isExpanded == false)
        #expect(navigation.entries[2].parent == .row("w"))
    }

    @Test func upAndDownStopAtTheEnds() {
        let navigation = RadarNavigation(sections: sections)
        #expect(navigation.handle(.down, focused: nil) == .focus(.header(.waiting)))
        #expect(navigation.handle(.up, focused: .header(.waiting)) == .none)
        #expect(navigation.handle(.down, focused: .header(.waiting)) == .focus(.row("w")))
        #expect(navigation.handle(.up, focused: .row("k")) == .focus(.header(.working)))
        #expect(navigation.handle(.down, focused: .earlier) == .none)
    }

    @Test func leftAndRightFoldAndGoToParent() {
        let navigation = RadarNavigation(sections: sections)
        #expect(navigation.handle(.left, focused: .header(.idle)) == .toggleGroup(.idle))
        #expect(navigation.handle(.right, focused: .header(.idle)) == .none)
        #expect(navigation.handle(.right, focused: .earlier) == .toggleEarlier)
        #expect(navigation.handle(.left, focused: .earlier) == .none)
        #expect(navigation.handle(.left, focused: .row("kid")) == .focus(.row("w")))
        #expect(navigation.handle(.left, focused: .row("w")) == .none)
        #expect(navigation.handle(.right, focused: .header(.waiting)) == .none)
    }

    @Test func spaceAndReturn() {
        let navigation = RadarNavigation(sections: sections)
        #expect(navigation.handle(.space, focused: .header(.idle)) == .toggleGroup(.idle))
        #expect(navigation.handle(.return, focused: .earlier) == .toggleEarlier)
        #expect(navigation.handle(.return, focused: .row("w")) == .showApp("w"))
        #expect(navigation.handle(.space, focused: .row("w")) == .toggleDetail("w"))
        #expect(navigation.handle(.return, focused: .header(.waiting)) == .none)
        #expect(navigation.handle(.escape, focused: .row("w")) == .focusSwitcher)
        #expect(navigation.handle(.escape, focused: nil) == .focusSwitcher)
    }

    @Test func focusSurvivesListChanges() {
        let before = RadarNavigation(sections: sections)
        let after = RadarNavigation(sections: [record("k", .working)].sections())
        #expect(after.resolve(.row("k"), previous: before) == .row("k"))
        #expect(after.resolve(.row("w"), previous: before) == .row("k"))
        #expect(after.resolve(nil) == .header(.working))
        #expect(RadarNavigation(entries: []).resolve(.row("k")) == nil)
        #expect(RadarNavigation(entries: []).handle(.down, focused: nil) == .none)
    }

    @Test func menubarRowsHaveRowKeysOnly() {
        let rows = [record("w", .waiting), record("k", .working)].menuRows(limit: 5).map(\.row)
        let navigation = RadarNavigation(rows: rows)
        #expect(navigation.entries.map(\.item) == [.row("w"), .row("k")])
        #expect(navigation.handle(.down, focused: .row("w")) == .focus(.row("k")))
        #expect(navigation.handle(.return, focused: .row("k")) == .showApp("k"))
    }

    // MARK: VoiceOver labels (SPEC 4.2)

    @Test func rowLabelReadsInOrder() {
        var waiting = record("app", .waiting, title: "Fix login", age: 120)
        waiting.waitingReason = "permission prompt"
        waiting.branch = "main"
        let text = SessionRowText(waiting, homeDirectory: "/Users/you")
        let label = RadarSpeech.rowLabel(waiting, text: text, parentTitle: nil, hasNoActivityFlag: false, now: now)
        #expect(label == "Fix login. Needs you. Permission prompt. app, main, Claude Code."
            + " Last activity 2 minutes ago.")
    }

    @Test func rowLabelAddsChildFlagAndStaleAndDropsEmptyParts() {
        var child = record("docs", .working, age: 1)
        child.isStale = true
        let text = SessionRowText(child, homeDirectory: "/Users/you", isNested: true)
        let label = RadarSpeech.rowLabel(
            child, text: text, parentTitle: "Fix login", hasNoActivityFlag: true, now: now
        )
        #expect(label == "docs. Working. Claude Code. Child session of Fix login. No activity for 1 second. Stale."
            + " Last activity 1 second ago.")
    }

    @Test func statusWords() {
        #expect(SessionStatus.allCases.map(RadarSpeech.statusWord)
            == ["Starting", "Working", "Needs you", "Idle", "Done", "Unknown"])
    }

    @Test(arguments: [(1, "1 second"), (45, "45 seconds"), (60, "1 minute"), (7_200, "2 hours"), (86_400, "1 day")]
          as [(TimeInterval, String)])
    func spokenDurations(age: TimeInterval, text: String) {
        #expect(RadarSpeech.duration(from: now.addingTimeInterval(-age), to: now) == text)
    }

    @Test func disclosureLabels() {
        #expect(RadarSpeech.disclosureLabel("Idle", count: 2) == "Idle, 2 sessions")
        #expect(RadarSpeech.disclosureLabel("Earlier", count: 1) == "Earlier, 1 session")
    }

    // MARK: Announcements (SPEC 4.1), injected clock

    private func title(_ record: SessionRecord) -> String { record.title ?? record.id }

    @Test func announcesOnlyAfterTheAlertDelayAndOnce() {
        var announcer = NeedsYouAnnouncer(alertDelay: 3)
        var waiting = record("a", .waiting, title: "Fix login")
        waiting.waitingReason = "permission prompt"
        #expect(announcer.update([waiting], now: now, title: title) == nil)
        #expect(announcer.update([waiting], now: now.addingTimeInterval(2.9), title: title) == nil)
        #expect(announcer.update([waiting], now: now.addingTimeInterval(3), title: title)
            == "Fix login needs you. Permission prompt.")
        #expect(announcer.update([waiting], now: now.addingTimeInterval(20), title: title) == nil)
    }

    @Test func shortWaitAndOtherStatesAreNeverAnnounced() {
        var announcer = NeedsYouAnnouncer(alertDelay: 3)
        #expect(announcer.update([record("a", .waiting)], now: now, title: title) == nil)
        // An auto-approved prompt: waiting for 2 s only.
        #expect(announcer.update([record("a", .working)], now: now.addingTimeInterval(2), title: title) == nil)
        #expect(announcer.update([record("a", .working)], now: now.addingTimeInterval(9), title: title) == nil)
        let quiet = [record("b", .idle), record("c", .done), record("d", .unknown)]
        #expect(announcer.update(quiet, now: now.addingTimeInterval(30), title: title) == nil)
    }

    @Test func severalAtOnceAreGroupedAndSpacedFiveSeconds() {
        var announcer = NeedsYouAnnouncer(alertDelay: 3)
        let two = [record("a", .waiting), record("b", .waiting)]
        _ = announcer.update(two, now: now, title: title)
        #expect(announcer.update(two, now: now.addingTimeInterval(3), title: title) == "2 sessions need you.")
        let three = two + [record("c", .waiting)]
        _ = announcer.update(three, now: now.addingTimeInterval(4), title: title)
        // c is due at 7 s, but the last announcement was at 3 s: held until 8 s.
        #expect(announcer.update(three, now: now.addingTimeInterval(7), title: title) == nil)
        #expect(announcer.update(three, now: now.addingTimeInterval(8), title: title) == "c needs you. Needs input.")
    }

    @Test func waitingAgainIsAnnouncedAgain() {
        var announcer = NeedsYouAnnouncer(alertDelay: 0)
        #expect(announcer.update([record("a", .waiting)], now: now, title: title) != nil)
        _ = announcer.update([record("a", .working)], now: now.addingTimeInterval(1), title: title)
        #expect(announcer.update([record("a", .waiting)], now: now.addingTimeInterval(6), title: title) != nil)
    }
}

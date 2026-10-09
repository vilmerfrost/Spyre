import Foundation
import Testing
@testable import SpyreCore

// All paths are fake.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let home = "/Users/you"

private func record(
    _ id: String, _ status: SessionStatus, cwd: String = "/Users/you/Projects/app", title: String? = nil,
    branch: String? = nil, ageSeconds: TimeInterval = 0
) -> SessionRecord {
    SessionRecord(
        id: id, agent: .claudeCode, workingDirectory: cwd, title: title, branch: branch, status: status,
        lastActivity: now.addingTimeInterval(-ageSeconds)
    )
}

@Suite(.timeLimit(.minutes(1)))
struct PresentationTests {
    // MARK: Row text (SPEC 4.2)

    @Test func titleWinsOverProjectName() {
        let text = SessionRowText(record("a", .idle, title: "Fix login bug"), homeDirectory: home)
        #expect(text.title == "Fix login bug")
        #expect(text.project == "app")
    }

    @Test(arguments: [nil, "", "   "])
    func missingTitleFallsBackToProjectName(title: String?) {
        #expect(SessionRowText(record("a", .idle, title: title), homeDirectory: home).title == "app")
    }

    @Test(arguments: ["/Users/you", "/Users/you/"])
    func homeFolderShowsTilde(cwd: String) {
        let text = SessionRowText(record("a", .idle, cwd: cwd), homeDirectory: home)
        #expect(text.project == "~")
        #expect(text.title == "~")
    }

    @Test func folderInsideHomeIsNotTilde() {
        #expect(SessionRowText(record("a", .idle, cwd: "/Users/you/you"), homeDirectory: home).project == "you")
    }

    @Test func unknownFolderFallsBackToAgentName() {
        let text = SessionRowText(record("a", .starting, cwd: ""), homeDirectory: home)
        #expect(text.project == nil)
        #expect(text.title == "Claude Code")
        #expect(text.detail == "Claude Code")
    }

    @Test(arguments: [("HEAD", nil), ("", nil), ("main", "main"), ("feat/x", "feat/x")] as [(String, String?)])
    func detachedHeadBranchIsHidden(branch: String, shown: String?) {
        #expect(SessionRowText(record("a", .idle, branch: branch), homeDirectory: home).branch == shown)
    }

    @Test func detailJoinsProjectBranchAndAgent() {
        let text = SessionRowText(record("a", .idle, title: "Fix login", branch: "main"), homeDirectory: home)
        #expect(text.detail == "app · main · Claude Code")
        let detached = SessionRowText(
            record("b", .idle, cwd: home, title: "Notes", branch: "HEAD"), homeDirectory: home
        )
        #expect(detached.detail == "~ · Claude Code")
    }

    @Test func detailDoesNotRepeatProjectUsedAsTitle() {
        let text = SessionRowText(record("a", .idle, branch: "main"), homeDirectory: home)
        #expect(text.title == "app")
        #expect(text.detail == "main · Claude Code")
    }

    @Test func tagsIncludeLabelChildMarksAndStale() {
        var child = record("c", .working)
        child.label = "exec"
        child.isChildSession = true
        child.parentID = "p"
        child.isStale = true
        #expect(SessionRowText(child, homeDirectory: home).tags == ["exec", "child session", "experimental", "stale"])
        #expect(SessionRowText(child, homeDirectory: home, isNested: true).tags == ["exec", "experimental", "stale"])
    }

    @Test func menuRowKeepsChildInParentsGroup() {
        var kid = record("kid", .idle)
        kid.isChildSession = true
        kid.parentID = "parent"
        let rows = [record("parent", .waiting), kid].menuRows(limit: 5)
        #expect(rows.map(\.row.id) == ["parent", "kid"])
        #expect(rows.map(\.group) == [.waiting, .waiting])
    }

    @Test func waitingTextIsSentenceCase() {
        var waiting = record("w", .waiting)
        waiting.waitingReason = "permission prompt"
        #expect(waiting.waitingText == "Permission prompt")
        waiting.waitingReason = nil
        #expect(waiting.waitingText == "Needs input")
        #expect(record("i", .idle).waitingText == nil)
    }

    @Test(arguments: [(0, "0 s"), (20, "20 s"), (59, "59 s"), (60, "1 min"), (299, "4 min"), (3_600, "1 h"),
                      (86_399, "23 h"), (172_800, "2 d"), (-5, "0 s")] as [(TimeInterval, String)])
    func relativeTimeIsShort(age: TimeInterval, text: String) {
        #expect(RelativeTime.short(from: now.addingTimeInterval(-age), to: now) == text)
    }

    // MARK: Count line

    @Test func countLineCountsNeedsYouWorkingAndIdle() {
        let sessions = [
            record("w1", .waiting), record("w2", .waiting), record("k", .working), record("s", .starting),
            record("i", .idle), record("d", .done), record("u", .unknown),
        ]
        let counts = SessionCounts(sessions)
        #expect(counts.needsYou == 2)
        #expect(counts.working == 2)
        #expect(counts.idle == 1)
        #expect(counts.needsYou == sessions.waitingCount)
    }

    // MARK: Sections and progressive disclosure

    @Test func idleAndDoneAreCollapsedByDefault() {
        let sessions = [record("w", .waiting), record("k", .working), record("i", .idle), record("d", .done),
                        record("u", .unknown)]
        let sections = sessions.sections()
        #expect(sections.map(\.group) == [.waiting, .working, .idle, .unknown, .done])
        #expect(sections.filter { !$0.isExpanded }.map(\.group) == [.idle, .done])
        #expect(sections.filter(\.isCollapsible).map(\.group) == [.idle, .done])
        #expect(sections.first { $0.group == .idle }?.visibleRows.isEmpty == true)
        #expect(sections.first { $0.group == .idle }?.rows.count == 1)
    }

    @Test func expandedGroupShowsItsRows() {
        let sections = [record("i", .idle), record("d", .done)].sections(expanded: [.idle])
        #expect(sections.first { $0.group == .idle }?.visibleRows.map(\.id) == ["i"])
        #expect(sections.first { $0.group == .done }?.visibleRows.isEmpty == true)
    }

    @Test func sectionCountLeavesOutNestedChildren() {
        var kid = record("kid", .idle)
        kid.isChildSession = true
        kid.parentID = "parent"
        let section = [record("parent", .waiting), kid].sections().first
        #expect(section?.rows.count == 2)
        #expect(section?.count == 1)
    }

    @Test func groupTitlesMatchSpec() {
        #expect(StatusGroup.allCases.map(\.title) == ["Needs you", "Working", "Idle", "Unknown", "Done"])
    }

    @Test func menuRowsShowNeedsYouThenWorkingUpToLimit() {
        let sessions = [
            record("i", .idle), record("k1", .working, ageSeconds: 5), record("k2", .working, ageSeconds: 50),
            record("w", .waiting, ageSeconds: 500), record("d", .done),
        ]
        #expect(sessions.menuRows(limit: 5).map(\.row.id) == ["w", "k1", "k2"])
        #expect(sessions.menuRows(limit: 5).map(\.group) == [.waiting, .working, .working])
        #expect(sessions.menuRows(limit: 2).map(\.row.id) == ["w", "k1"])
        #expect(sessions.menuRows(limit: 0).isEmpty)
    }

    // MARK: Atmosphere geometry

    @Test func ridgesStayInsideTheViewAndFarRidgeIsHighest() throws {
        #expect(Atmosphere.ridges.count == 3)
        for ridge in Atmosphere.ridges {
            #expect(ridge.heights.count == Atmosphere.samples)
            #expect(ridge.heights.allSatisfy { (0...1).contains($0) })
        }
        let tops = Atmosphere.ridges.map { $0.heights.min() ?? 1 }
        #expect(tops == tops.sorted())
    }
}

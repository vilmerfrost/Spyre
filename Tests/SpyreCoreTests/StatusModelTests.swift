import Foundation
import Testing
@testable import SpyreCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func record(_ id: String, _ status: SessionStatus, ageSeconds: TimeInterval = 0) -> SessionRecord {
    SessionRecord(
        id: id, agent: .claudeCode, workingDirectory: "/Users/you/Projects/app",
        status: status, lastActivity: now.addingTimeInterval(-ageSeconds)
    )
}

private func child(_ id: String, of parent: String?, _ status: SessionStatus, ageSeconds: TimeInterval = 0)
    -> SessionRecord {
    var child = record(id, status, ageSeconds: ageSeconds)
    child.isChildSession = true
    child.parentID = parent
    return child
}

@Suite(.timeLimit(.minutes(1)))
struct StatusModelTests {
    @Test func onlyWaitingCountsInBadge() {
        #expect(SessionStatus.allCases.filter(\.countsInBadge) == [.waiting])
    }

    @Test func waitingCountIgnoresOtherStatuses() {
        let sessions = SessionStatus.allCases.map { record($0.rawValue, $0) } + [record("w2", .waiting)]
        #expect(sessions.waitingCount == 2)
    }

    @Test func groupsFollowSpecOrder() {
        let sessions = [record("d", .done), record("i", .idle), record("w", .waiting), record("u", .unknown), record("k", .working)]
        #expect(sessions.grouped().map(\.group) == [.waiting, .working, .idle, .unknown, .done])
    }

    @Test func emptyGroupsAreLeftOut() {
        #expect([record("i", .idle)].grouped().map(\.group) == [.idle])
    }

    @Test func startingShowsInWorkingGroup() {
        #expect(SessionStatus.starting.group == .working)
    }

    @Test func newestActivityComesFirstInGroup() {
        let sessions = [record("old", .idle, ageSeconds: 600), record("new", .idle, ageSeconds: 5)]
        #expect(sessions.grouped().first?.rows.map(\.id) == ["new", "old"])
    }

    @Test func noActivityFlagOnlyOnWorkingAfterThreshold() {
        let config = SpyreConfig.default
        #expect(record("a", .working, ageSeconds: 601).hasNoActivityFlag(now: now, config: config))
        #expect(!record("b", .working, ageSeconds: 599).hasNoActivityFlag(now: now, config: config))
        #expect(!record("c", .waiting, ageSeconds: 3600).hasNoActivityFlag(now: now, config: config))
    }

    @Test func unknownRawValueDoesNotDecode() {
        #expect(SessionStatus(rawValue: "stuck") == nil)
    }

    @Test func projectNameIsLastPathComponent() {
        #expect(record("a", .idle).projectName == "app")
    }

    @Test func configDefaultsMatchSpec() {
        let config = SpyreConfig.default
        #expect(config.alertDelay == 3)
        #expect(config.noActivityThreshold == 600)
        #expect(config.adapterRefreshTimeout == 2)
    }

    // MARK: Child rows (SPEC 4.2, 4.6)

    @Test func childShowsUnderParentInParentsGroup() {
        let sessions = [record("parent", .waiting), child("kid", of: "parent", .working), record("other", .working)]
        let groups = sessions.grouped()
        #expect(groups.map(\.group) == [.waiting, .working])
        #expect(groups[0].rows.map(\.id) == ["parent", "kid"])
        #expect(groups[0].rows.map(\.isNested) == [false, true])
        #expect(groups[1].rows.map(\.id) == ["other"])
    }

    @Test func childrenUnderOneParentAreNewestFirst() {
        let sessions = [
            record("parent", .idle, ageSeconds: 100),
            child("old", of: "parent", .idle, ageSeconds: 50),
            child("new", of: "parent", .idle, ageSeconds: 5),
        ]
        #expect(sessions.grouped().first?.rows.map(\.id) == ["parent", "new", "old"])
    }

    @Test func childWithoutParentInListIsTopLevel() {
        let sessions = [child("orphan", of: nil, .working), child("lost", of: "gone", .idle)]
        let groups = sessions.grouped()
        #expect(groups.map(\.group) == [.working, .idle])
        #expect(groups.flatMap(\.rows).allSatisfy { !$0.isNested })
    }

    @Test func nestingKeepsEveryRowOnceAndBadgeCountsChildren() {
        let sessions = [record("parent", .idle), child("kid", of: "parent", .waiting), record("solo", .waiting)]
        let ids = sessions.grouped().flatMap(\.rows).map(\.id)
        #expect(ids.sorted() == ["kid", "parent", "solo"])
        #expect(sessions.waitingCount == 2)
    }

    @Test func nonChildWithParentIDIsNotNested() {
        var plain = record("plain", .idle)
        plain.parentID = "parent"
        let rows = [record("parent", .idle), plain].grouped().flatMap(\.rows)
        #expect(rows.allSatisfy { !$0.isNested })
    }
}

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
        #expect(sessions.grouped().first?.sessions.map(\.id) == ["new", "old"])
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
}

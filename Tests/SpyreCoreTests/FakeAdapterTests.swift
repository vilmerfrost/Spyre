import Foundation
import Testing
@testable import SpyreCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite(.timeLimit(.minutes(1)))
struct FakeAdapterTests {
    @Test func fakeAdapterIsObserveOnly() {
        let adapter = FakeAdapter { now }
        #expect(adapter.capabilities == .observe)
        #expect(!adapter.capabilities.contains(.steer))
        #expect(!adapter.capabilities.contains(.approve))
        #expect(!adapter.capabilities.contains(.stop))
    }

    @Test func fakeAdapterReturnsFixedSessions() async {
        let snapshot = await FakeAdapter { now }.refresh()
        #expect(snapshot.sessions.count == 6)
        #expect(snapshot.sessions.waitingCount == 2)
        #expect(snapshot.diagnostics.isEmpty)
        #expect(snapshot.formatVersions["fake"] == "1")
    }

    @Test func fakeAdapterIsDeterministic() async {
        let adapter = FakeAdapter { now }
        let first = await adapter.refresh()
        let second = await adapter.refresh()
        #expect(first == second)
    }

    @Test func fakeSessionsAreObservedAndUseFakePaths() {
        for session in FakeAdapter.sessions(now: now) {
            #expect(session.kind == .observed)
            #expect(session.workingDirectory.hasPrefix("/Users/you/"))
        }
    }

    @Test func fakeSessionsCoverEveryGroup() {
        let groups = Set(FakeAdapter.sessions(now: now).map(\.status.group))
        #expect(groups == Set(StatusGroup.allCases))
    }
}

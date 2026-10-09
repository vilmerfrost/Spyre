import Foundation
import os
import Testing
@testable import SpyreCore

// All data is fake: `/Users/you/...` paths and made-up IDs.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// An adapter whose sessions the test sets. While `hang` is on, `refresh()` does not return.
private final class StubAdapter: AgentAdapter {
    let agent: AgentType = .codex
    let capabilities: AdapterCapabilities = .observe
    private let state = OSAllocatedUnfairLock(initialState: (sessions: [SessionRecord](), hang: false))

    func set(_ sessions: [SessionRecord]) { state.withLock { $0.sessions = sessions } }
    func setHang(_ hang: Bool) { state.withLock { $0.hang = hang } }

    func refresh() async -> AdapterSnapshot {
        while state.withLock({ $0.hang }) { try? await Task.sleep(for: .milliseconds(10)) }
        return AdapterSnapshot(sessions: state.withLock { $0.sessions })
    }

    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// A clock and a timeout the test controls. With `fastTimeout` off, a refresh never times out in a test.
private final class Controls: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (now: t0, fastTimeout: false))
    var now: Date { state.withLock { $0.now } }
    func advance(_ seconds: TimeInterval) { state.withLock { $0.now += seconds } }
    func setFastTimeout(_ fast: Bool) { state.withLock { $0.fastTimeout = fast } }

    func sleep() async {
        if state.withLock({ $0.fastTimeout }) { return }
        try? await Task.sleep(for: .seconds(50))
    }
}

private func codex(_ id: String, _ status: SessionStatus, at date: Date = t0) -> SessionRecord {
    SessionRecord(id: id, agent: .codex, workingDirectory: "/Users/you/Projects/\(id)", status: status,
                  lastActivity: date)
}

private func makeStore(_ adapters: [any AgentAdapter], _ controls: Controls,
                       config: SpyreConfig = .default) -> SessionStore {
    SessionStore(adapters: adapters, config: config, now: { controls.now }, sleep: { _ in await controls.sleep() })
}

@Suite(.timeLimit(.minutes(1)))
struct SessionStoreTests {
    @Test func mergesTwoAdapters() async {
        let controls = Controls()
        let stub = StubAdapter()
        stub.set([codex("api", .working)])
        let store = makeStore([FakeAdapter(now: { t0 }), stub], controls)
        await store.refresh(0)
        await store.refresh(1)

        let sessions = await store.sessions()
        let fake = FakeAdapter.sessions(now: t0).filter { $0.status != .done }
        #expect(sessions.filter { $0.id.hasPrefix("fake-") && $0.status != .done }.map(\.id) == fake.map(\.id))
        #expect(sessions.contains { $0.id == "api" && $0.agent == .codex })
        #expect(sessions.waitingCount == 2)
    }

    @Test func timeoutKeepsLastSnapshotMarkedStale() async {
        let controls = Controls()
        let stub = StubAdapter()
        stub.set([codex("api", .waiting)])
        let store = makeStore([stub], controls)
        await store.refresh(0)
        #expect(await store.sessions().map(\.isStale) == [false])

        stub.setHang(true)
        controls.setFastTimeout(true)
        await store.refresh(0)
        let stale = await store.sessions()
        #expect(stale.map(\.isStale) == [true])
        #expect(stale.waitingCount == 1)

        // The late result clears the stale mark.
        stub.set([codex("api", .idle)])
        stub.setHang(false)
        var updates = store.updates.makeAsyncIterator()
        var latest = await updates.next()
        while let sessions = latest, sessions.first?.isStale != false { latest = await updates.next() }
        #expect(latest?.map(\.status) == [.idle])
    }

    @Test func doneRowHidesAfterDoneRowTimeout() async {
        let controls = Controls()
        let stub = StubAdapter()
        stub.set([codex("api", .working)])
        let store = makeStore([stub], controls)
        await store.refresh(0)

        controls.advance(60)
        stub.set([codex("api", .done)])
        await store.refresh(0)
        controls.advance(SpyreConfig.default.doneRowTimeout)
        #expect(await store.sessions().map(\.status) == [.done])
        controls.advance(1)
        #expect(await store.sessions().isEmpty)

        await store.update(config: SpyreConfig(doneRowTimeout: 3_600))
        #expect(await store.sessions().map(\.id) == ["api"])
    }

    @Test func doneOnFirstSightCountsFromLastActivity() async {
        let controls = Controls()
        let stub = StubAdapter()
        let config = SpyreConfig(doneRowTimeout: 120)
        stub.set([
            codex("old", .done, at: t0.addingTimeInterval(-121)),
            codex("new", .done, at: t0.addingTimeInterval(-60)),
        ])
        let store = makeStore([stub], controls, config: config)
        await store.refresh(0)
        #expect(await store.sessions().map(\.id) == ["new"])
    }

    @Test func labelsPassThroughToRowTags() async {
        let controls = Controls()
        let stub = StubAdapter()
        var exec = codex("exec", .working)
        exec.label = "exec"
        var child = codex("child", .idle)
        child.isChildSession = true
        var orphan = child
        orphan.id = "orphan"
        child.parentID = "parent"
        stub.set([exec, child, orphan])
        let store = makeStore([stub], controls)
        await store.refresh(0)

        let tags = Dictionary(uniqueKeysWithValues: await store.sessions().map { ($0.id, $0.tags) })
        #expect(tags["exec"] == ["exec"])
        #expect(tags["child"] == ["child session", "experimental"])
        #expect(tags["orphan"] == ["child, no parent", "experimental"])
    }
}

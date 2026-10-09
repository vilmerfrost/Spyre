import Foundation
import os

/// Merges the snapshots of all adapters into the one session list the app shows. `SPEC.md` 4.4 and 6.4.
///
/// - Refreshes one adapter on each of its `changes()` signals. One refresh per adapter at a time.
/// - A refresh slower than `adapterRefreshTimeout` keeps that adapter's last snapshot and marks its rows stale.
/// - Hides `done` rows `doneRowTimeout` seconds after the session ended.
/// All work runs on this actor, never on the main actor. The app reads `updates`.
public actor SessionStore {
    /// Waits the given number of seconds. Tests inject a fake.
    public typealias Sleep = @Sendable (TimeInterval) async -> Void

    private static let logger = Logger(subsystem: "io.github.vilmerfrost.spyre", category: "store")

    private let adapters: [any AgentAdapter]
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    private var config: SpyreConfig
    private var snapshots: [[SessionRecord]]
    private var inFlight = Set<Int>()
    /// Every session key in the current snapshots, with the time it became `done` (or `nil`).
    private var doneSince: [String: Date?] = [:]
    private let continuation: AsyncStream<[SessionRecord]>.Continuation

    /// The visible sessions, sent after each change.
    public nonisolated let updates: AsyncStream<[SessionRecord]>

    public init(
        adapters: [any AgentAdapter],
        config: SpyreConfig = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleep = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.adapters = adapters
        self.config = config
        self.now = now
        self.sleep = sleep
        snapshots = adapters.map { _ in [] }
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Refreshes every adapter once, then again on each of its change signals. Returns when cancelled.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            for index in adapters.indices {
                let stream = adapters[index].changes()
                group.addTask {
                    await self.refresh(index)
                    for await _ in stream { await self.refresh(index) }
                }
            }
        }
    }

    public func update(config: SpyreConfig) {
        self.config = config
        publish()
    }

    /// Refreshes one adapter. Skips the call when the last refresh of that adapter has not returned yet.
    public func refresh(_ index: Int) async {
        guard adapters.indices.contains(index), !inFlight.contains(index) else { return }
        inFlight.insert(index)
        let adapter = adapters[index]
        let work = Task { await adapter.refresh() }
        if let snapshot = await Self.value(of: work, timeout: config.adapterRefreshTimeout, sleep: sleep) {
            finish(index, snapshot)
            return
        }
        Self.logger.warning("Adapter \(adapter.agent.rawValue, privacy: .public) refresh timed out")
        snapshots[index] = snapshots[index].map { var record = $0; record.isStale = true; return record }
        publish()
        Task { self.finish(index, await work.value) }
    }

    /// The merged sessions without hidden `done` rows.
    public func sessions() -> [SessionRecord] {
        let time = now()
        return snapshots.joined().filter { record in
            guard record.status == .done, let since = doneSince[Self.key(record)] ?? nil else { return true }
            return time.timeIntervalSince(since) <= config.doneRowTimeout
        }
    }

    private func finish(_ index: Int, _ snapshot: AdapterSnapshot) {
        inFlight.remove(index)
        snapshots[index] = snapshot.sessions
        publish()
    }

    private func publish() {
        let time = now()
        var next: [String: Date?] = [:]
        for record in snapshots.joined() {
            let key = Self.key(record)
            guard record.status == .done else { next[key] = .some(nil); continue }
            switch doneSince[key] {
            case .some(.some(let since)): next[key] = since
            // A row seen for the first time as `done` ended at its last activity.
            case .none: next[key] = min(record.lastActivity, time)
            case .some(.none): next[key] = time
            }
        }
        doneSince = next
        continuation.yield(sessions())
    }

    private static func key(_ record: SessionRecord) -> String { "\(record.agent.rawValue):\(record.id)" }

    /// The task's value, or `nil` when `timeout` passes first. The task keeps running after a timeout.
    private static func value<T: Sendable>(
        of work: Task<T, Never>, timeout: TimeInterval, sleep: @escaping Sleep
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let pending = OSAllocatedUnfairLock<CheckedContinuation<T?, Never>?>(initialState: continuation)
            let resume: @Sendable (T?) -> Void = { value in
                pending.withLock { saved in
                    saved?.resume(returning: value)
                    saved = nil
                }
            }
            Task { resume(await work.value) }
            Task {
                await sleep(timeout)
                resume(nil)
            }
        }
    }
}

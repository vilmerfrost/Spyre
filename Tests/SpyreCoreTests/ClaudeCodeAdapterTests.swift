import Foundation
import os
import Testing
@testable import SpyreCore

// All fixture data is fake: `/Users/you/...` paths and zero UUIDs.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let uuid = "00000000-0000-0000-0000-000000000"
private let cliPath = "/Users/you/.local/share/claude/versions/2.1.295"

private final class TestClock: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: t0)
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 += seconds } }
}

private func claude(_ pid: Int32, parent: Int32 = 50, path: String = cliPath, start: Date = t0) -> ScannedProcess {
    ScannedProcess(pid: pid, parentPID: parent, executablePath: path, startTime: start)
}

private struct Harness {
    let root: URL
    let clock = TestClock()
    let processes = FakeProcessScanner()
    let adapter: ClaudeCodeAdapter

    /// Copies the named session files and all transcripts into a fresh temp folder.
    init(sessions: [String]) throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude/2.1.295")
        let manager = FileManager.default
        root = manager.temporaryDirectory.appendingPathComponent("spyre-claude-\(UUID().uuidString)")
        try manager.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try manager.copyItem(
            at: fixtures.appendingPathComponent("projects"), to: root.appendingPathComponent("projects")
        )
        for name in sessions {
            try manager.copyItem(
                at: fixtures.appendingPathComponent("sessions/\(name)"),
                to: root.appendingPathComponent("sessions/\(name)")
            )
        }
        let clock = clock
        adapter = ClaudeCodeAdapter(claudeRoot: root, processes: processes, now: { clock.now })
    }

    func session(_ file: String) -> URL { root.appendingPathComponent("sessions/\(file)") }

    func refresh() async -> [String: SessionRecord] {
        Dictionary(uniqueKeysWithValues: await adapter.refresh().sessions.map { ($0.id, $0) })
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Suite(.timeLimit(.minutes(1)))
struct ClaudeCodeAdapterTests {
    @Test func claudeAdapterIsObserveOnly() throws {
        let harness = try Harness(sessions: [])
        defer { harness.cleanUp() }
        #expect(harness.adapter.capabilities == .observe)
        #expect(harness.adapter.agent == .claudeCode)
    }

    @Test func validRegistryFilesMapStatus() async throws {
        let harness = try Harness(sessions: ["101.json", "101.0000000000000000.key", "102.json", "106.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(101), claude(102), claude(106)])

        let snapshot = await harness.adapter.refresh()
        let sessions = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
        #expect(sessions.count == 3)
        #expect(snapshot.diagnostics.isEmpty)
        #expect(snapshot.formatVersions["claude.registry"] == "2.1.295")

        let busy = try #require(sessions["\(uuid)101"])
        #expect(busy.status == .working)
        #expect(busy.workingDirectory == "/Users/you/Projects/app")
        #expect(busy.branch == "feat/login")
        #expect(busy.lastActivity == t0.addingTimeInterval(90.5))
        #expect(busy.kind == .observed && !busy.isChildSession)
        #expect(busy.title == "Fake session")

        let waiting = try #require(sessions["\(uuid)102"])
        #expect(waiting.status == .waiting)
        #expect(waiting.waitingReason == "permission prompt")
        #expect(waiting.title == nil)

        #expect(sessions["\(uuid)106"]?.status == .unknown)
    }

    /// The detail line: host from `entrypoint`, start from `startedAt`, and the PID for "Show app".
    @Test func registryGivesHostStartAndProcessID() async throws {
        let harness = try Harness(sessions: ["101.json", "102.json", "106.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(101), claude(102), claude(106)])
        let sessions = await harness.refresh()
        #expect(sessions["\(uuid)101"]?.host == .cli)
        #expect(sessions["\(uuid)102"]?.host == .desktop)
        #expect(sessions["\(uuid)106"]?.host == .vscode)
        #expect(sessions["\(uuid)101"]?.processID == 101)
        #expect(sessions["\(uuid)101"]?.startedAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(sessions["\(uuid)101"]?.agentVersion == nil)
    }

    @Test func missingStatusIsStartingThenUnknownAfterTimeout() async throws {
        let harness = try Harness(sessions: ["103.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(103)])

        let first = try #require(await harness.refresh()["\(uuid)103"])
        #expect(first.status == .starting)
        #expect(first.workingDirectory == "/Users/you/Projects/site")
        harness.clock.advance(1.9)
        #expect(await harness.refresh()["\(uuid)103"]?.status == .starting)
        harness.clock.advance(0.1)
        #expect(await harness.refresh()["\(uuid)103"]?.status == .unknown)
    }

    @Test func truncatedNewFileIsStartingWithDiagnostic() async throws {
        let harness = try Harness(sessions: ["104.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(104)])

        let snapshot = await harness.adapter.refresh()
        #expect(snapshot.sessions.map(\.id) == ["claude-pid-104"])
        #expect(snapshot.sessions.first?.status == .starting)
        #expect(snapshot.diagnostics.count == 1)
    }

    @Test func badReadKeepsLastKnownState() async throws {
        let harness = try Harness(sessions: ["102.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(102)])
        #expect(await harness.refresh()["\(uuid)102"]?.status == .waiting)

        let file = harness.session("102.json")
        let full = try Data(contentsOf: file)
        try full.prefix(60).write(to: file)
        harness.clock.advance(5)
        let afterPartial = try #require(await harness.refresh()["\(uuid)102"])
        #expect(afterPartial.status == .waiting)
        #expect(afterPartial.waitingReason == "permission prompt")

        try Data(#"{"pid":102,"sessionId":"\#(uuid)102"}"#.utf8).write(to: file)
        #expect(await harness.refresh()["\(uuid)102"]?.status == .waiting)

        try full.write(to: file)
        #expect(await harness.refresh()["\(uuid)102"]?.status == .waiting)
    }

    @Test func deadProcessGivesDone() async throws {
        let harness = try Harness(sessions: ["101.json", "105.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(101)])
        let first = await harness.refresh()
        #expect(first["\(uuid)101"]?.status == .working)
        #expect(first["\(uuid)105"]?.status == .done)

        harness.processes.set([])
        let second = await harness.refresh()
        #expect(second["\(uuid)101"]?.status == .done)
        #expect(second["\(uuid)101"]?.waitingReason == nil)
    }

    @Test func deletedFileGivesDoneThenRowIsRemoved() async throws {
        let harness = try Harness(sessions: ["101.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(101)])
        #expect(await harness.refresh()["\(uuid)101"]?.status == .working)

        try FileManager.default.removeItem(at: harness.session("101.json"))
        #expect(await harness.refresh()["\(uuid)101"]?.status == .done)
        harness.clock.advance(ClaudeCodeAdapter.doneRetention + 1)
        #expect(await harness.refresh()["\(uuid)101"] == nil)
    }

    @Test func reusedPIDGivesDone() async throws {
        let harness = try Harness(sessions: ["101.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(101, start: t0.addingTimeInterval(1))])
        #expect(await harness.refresh()["\(uuid)101"]?.status == .working)

        harness.processes.set([claude(101, start: t0.addingTimeInterval(3_600))])
        #expect(await harness.refresh()["\(uuid)101"]?.status == .done)
    }

    @Test func pidReuseFallsBackToProcStart() {
        let entry = ClaudeRegistryEntry(procStart: "Fri Jan 15 08:00:00 2027")
        #expect(entry.procStartDate == t0)
        #expect(!ClaudeCodeAdapter.isReused(entry, process: claude(1, start: t0)))
        #expect(ClaudeCodeAdapter.isReused(entry, process: claude(1, start: t0.addingTimeInterval(60))))
        #expect(!ClaudeCodeAdapter.isReused(ClaudeRegistryEntry(procStart: "12345"), process: claude(1, start: .now)))
    }

    @Test func childSessionFindsParentAndTranscriptStatus() async throws {
        let harness = try Harness(sessions: ["101.json"])
        defer { harness.cleanUp() }
        let shell = ScannedProcess(pid: 900, parentPID: 101, executablePath: "/bin/zsh")
        harness.processes.set([claude(101), shell, claude(201, parent: 900)], cwds: [201: "/Users/you/Projects/app"])

        let child = try #require(await harness.refresh()["claude-child-201"])
        #expect(child.isChildSession)
        #expect(child.parentID == "\(uuid)101")
        #expect(child.status == .working)
        #expect(child.branch == "main")
        #expect(child.lastActivity == t0.addingTimeInterval(180))
    }

    @Test func childSessionWithoutParentUsesTurnEnd() async throws {
        let harness = try Harness(sessions: [])
        defer { harness.cleanUp() }
        let vscode = "/Users/you/.vscode/extensions/anthropic.claude-code-2.1.295/resources/native-binary/claude"
        harness.processes.set([claude(202, parent: 1, path: vscode)], cwds: [202: "/Users/you/Projects/docs"])

        let child = try #require(await harness.refresh()["claude-child-202"])
        #expect(child.isChildSession && child.parentID == nil)
        #expect(child.status == .idle)
        #expect(child.branch == "docs/readme")
    }

    @Test func unreadableChildIsUnknownThenDone() async throws {
        let harness = try Harness(sessions: [])
        defer { harness.cleanUp() }
        harness.processes.set([claude(203), ScannedProcess(pid: 204, parentPID: 1, executablePath: "/usr/bin/node")])

        let snapshot = await harness.adapter.refresh()
        #expect(snapshot.sessions.map(\.id) == ["claude-child-203"])
        #expect(snapshot.sessions.first?.status == .unknown)
        #expect(snapshot.diagnostics.count == 1)

        harness.processes.set([])
        #expect(await harness.refresh()["claude-child-203"]?.status == .done)
    }

    @Test func childRowIsDroppedWhenRegistryFileAppears() async throws {
        let harness = try Harness(sessions: [])
        defer { harness.cleanUp() }
        harness.processes.set([claude(101)], cwds: [101: "/Users/you/Projects/app"])
        #expect(await harness.refresh()["claude-child-101"] != nil)

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude/2.1.295/sessions/101.json")
        try FileManager.default.copyItem(at: fixture, to: harness.session("101.json"))
        let rows = await harness.refresh()
        #expect(rows.keys.sorted() == ["\(uuid)101"])
    }

    @Test func exitingSessionDoesNotBecomeChild() async throws {
        let harness = try Harness(sessions: ["101.json"])
        defer { harness.cleanUp() }
        harness.processes.set([claude(101)], cwds: [101: "/Users/you/Projects/app"])
        #expect(await harness.refresh()["\(uuid)101"]?.status == .working)

        // `/exit` deletes the registry file while the process still runs for a moment.
        try FileManager.default.removeItem(at: harness.session("101.json"))
        let rows = await harness.refresh()
        #expect(rows.keys.sorted() == ["\(uuid)101"])
        #expect(rows["\(uuid)101"]?.status == .done)
    }

    @Test func childCandidateWithoutTranscriptIsNotShown() async throws {
        let harness = try Harness(sessions: [])
        defer { harness.cleanUp() }
        harness.processes.set([claude(205, parent: 1)], cwds: [205: "/Users/you/Projects/empty"])

        let snapshot = await harness.adapter.refresh()
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.diagnostics.count == 1)
    }

    @Test func claudeExecutableMatchesByPath() {
        let desktop = "/Users/you/Library/Application Support/Claude/claude-code/2.1.295/x/"
            + "claude.app/Contents/MacOS/claude"
        let match = [cliPath, desktop]
        let noMatch = ["/usr/bin/node", "/Users/you/.local/share/claude/versions/", "/bin/claude-helper", "/bin/zsh"]
        for path in match { #expect(ClaudeCodeAdapter.isClaudeCode(path)) }
        for path in noMatch { #expect(!ClaudeCodeAdapter.isClaudeCode(path)) }
    }

    @Test func transcriptFolderNameEncodesCwd() {
        #expect(ClaudeTranscriptReader.encodedFolderName(for: "/Users/you/Projects/app") == "-Users-you-Projects-app")
        #expect(ClaudeTranscriptReader.encodedFolderName(for: "/Users/you/.config/x_y") == "-Users-you--config-x-y")
    }
}

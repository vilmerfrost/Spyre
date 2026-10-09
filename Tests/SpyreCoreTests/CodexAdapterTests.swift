import Foundation
import SQLite3
import Testing
@testable import SpyreCore

// All IDs and paths are fake. Tests never read the real `~/.codex`.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/codex/0.161.0")

private func fakeID(_ n: Int) -> String { String(format: "00000000-0000-0000-0000-%012d", n) }

private struct FakeProcesses: CodexProcessProvider {
    var list: [CodexProcess]
    func codexProcesses() -> [CodexProcess] { list }
}

private func tui(_ pid: Int32, _ cwd: String) -> CodexProcess {
    CodexProcess(pid: pid, executablePath: "/opt/homebrew/bin/codex", workingDirectory: cwd,
                 hasControllingTerminal: true)
}

private struct Row {
    var id: String
    var cwd: String
    var rollout: String
    var updated: Date
    var archived = false
}

/// A temp Codex root with a `state_5.sqlite` built at runtime.
private func makeRoot(_ rows: [Row], database: Bool = true) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("spyre-codex-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    guard database else { return root }
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    let path = root.appendingPathComponent("state_5.sqlite").path
    try #require(sqlite3_open(path, &db) == SQLITE_OK)
    var sql = """
        CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, cwd TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '', git_branch TEXT, updated_at_ms INTEGER,
        archived INTEGER NOT NULL DEFAULT 0, cli_version TEXT NOT NULL DEFAULT '');
        """
    for row in rows {
        let rollout = fixtures.appendingPathComponent(row.rollout).path
        let millis = Int64(row.updated.timeIntervalSince1970 * 1000)
        sql += """
            INSERT INTO threads (id, rollout_path, cwd, git_branch, updated_at_ms, archived, cli_version)
            VALUES ('\(row.id)', '\(rollout)', '\(row.cwd)', 'main', \(millis), \(row.archived ? 1 : 0), '0.161.0');
            """
    }
    try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    return root
}

private func snapshot(_ rows: [Row], _ processes: [CodexProcess], database: Bool = true) async throws
    -> AdapterSnapshot {
    let root = try makeRoot(rows, database: database)
    defer { try? FileManager.default.removeItem(at: root) }
    return await CodexAdapter(codexRoot: root, processes: FakeProcesses(list: processes), now: { now }).refresh()
}

@Suite(.timeLimit(.minutes(1)))
struct CodexAdapterTests {
    @Test func codexAdapterIsObserveOnly() throws {
        let adapter = CodexAdapter(codexRoot: URL(fileURLWithPath: "/nonexistent"), processes: FakeProcesses(list: []))
        #expect(adapter.agent == .codex)
        #expect(adapter.capabilities == .observe)
    }

    @Test func liveTUIWithTaskStartedIsWorking() async throws {
        let rows = [Row(id: fakeID(1), cwd: "/Users/you/Projects/api", rollout: "rollout-working.jsonl",
                        updated: now.addingTimeInterval(-30))]
        let result = try await snapshot(rows, [tui(101, "/Users/you/Projects/api/")])
        let session = try #require(result.sessions.first)
        #expect(result.sessions.count == 1)
        #expect(session.id == fakeID(1))
        #expect(session.status == .working)
        #expect(session.branch == "main")
        #expect(session.kind == .observed)
        #expect(result.diagnostics.isEmpty)
        #expect(result.formatVersions == ["codex.state": "5", "codex.cli": "0.161.0"])
    }

    @Test func liveTUIAfterTaskCompleteOrAbortIsIdle() async throws {
        let rows = [
            Row(id: fakeID(2), cwd: "/Users/you/Projects/web", rollout: "rollout-idle.jsonl", updated: now),
            Row(id: fakeID(3), cwd: "/Users/you/Projects/cli", rollout: "rollout-aborted.jsonl", updated: now),
        ]
        let result = try await snapshot(rows, [tui(1, "/Users/you/Projects/web"), tui(2, "/Users/you/Projects/cli")])
        #expect(result.sessions.map(\.status) == [.idle, .idle])
    }

    @Test func threadWithoutLiveTUIIsDoneThenDropped() async throws {
        let rows = [
            Row(id: fakeID(4), cwd: "/Users/you/Projects/api", rollout: "rollout-working.jsonl",
                updated: now.addingTimeInterval(-60)),
            Row(id: fakeID(5), cwd: "/Users/you/Projects/old", rollout: "rollout-idle.jsonl",
                updated: now.addingTimeInterval(-3600)),
            Row(id: fakeID(6), cwd: "/Users/you/Projects/arch", rollout: "rollout-idle.jsonl", updated: now,
                archived: true),
        ]
        let result = try await snapshot(rows, [])
        #expect(result.sessions.map(\.id) == [fakeID(4)])
        #expect(result.sessions.first?.status == .done)
    }

    @Test func killedProcessGivesDone() async throws {
        // The rollout still says `working`: a killed TUI writes no exit record. The process table decides.
        let rows = [Row(id: fakeID(7), cwd: "/Users/you/Projects/api", rollout: "rollout-working.jsonl",
                        updated: now.addingTimeInterval(-5))]
        let alive = try await snapshot(rows, [tui(200, "/Users/you/Projects/api")])
        let killed = try await snapshot(rows, [])
        #expect(alive.sessions.first?.status == .working)
        #expect(killed.sessions.first?.status == .done)
    }

    @Test func serverProcessesDoNotCountAsLive() async throws {
        let rows = [Row(id: fakeID(8), cwd: "/Users/you/Projects/api", rollout: "rollout-working.jsonl", updated: now)]
        let servers = [
            CodexProcess(pid: 1, executablePath: "/opt/homebrew/bin/codex", workingDirectory: "/Users/you/Projects/api",
                         hasControllingTerminal: false),
            CodexProcess(pid: 2, executablePath: "/opt/homebrew/bin/codex-helper",
                         workingDirectory: "/Users/you/Projects/api", hasControllingTerminal: true),
        ]
        let result = try await snapshot(rows, servers)
        #expect(result.sessions.first?.status == .done)
    }

    @Test func twoTUIsInOneFolderShowAsOneSession() async throws {
        let rows = [
            Row(id: fakeID(9), cwd: "/Users/you/Projects/api", rollout: "rollout-idle.jsonl",
                updated: now.addingTimeInterval(-120)),
            Row(id: fakeID(10), cwd: "/Users/you/Projects/api", rollout: "rollout-working.jsonl",
                updated: now.addingTimeInterval(-10)),
        ]
        let result = try await snapshot(rows, [tui(1, "/Users/you/Projects/api"), tui(2, "/Users/you/Projects/api")])
        #expect(result.sessions.map(\.id) == [fakeID(10)])
        #expect(result.sessions.first?.status == .working)
    }

    @Test func corruptRolloutGivesUnknownWithDiagnostic() async throws {
        let rows = [
            Row(id: fakeID(11), cwd: "/Users/you/Projects/a", rollout: "rollout-corrupt.jsonl", updated: now),
            Row(id: fakeID(12), cwd: "/Users/you/Projects/b", rollout: "missing.jsonl", updated: now),
        ]
        let result = try await snapshot(rows, [tui(1, "/Users/you/Projects/a"), tui(2, "/Users/you/Projects/b")])
        #expect(result.sessions.map(\.status) == [.unknown, .unknown])
        #expect(result.diagnostics.count == 2)
    }

    @Test func missingDatabaseGivesDiagnosticAndUnknownLiveFolders() async throws {
        let empty = try await snapshot([], [], database: false)
        #expect(empty.sessions.isEmpty)
        #expect(empty.diagnostics.map(\.source) == ["codex.state"])

        let live = try await snapshot([], [tui(1, "/Users/you/Projects/api")], database: false)
        #expect(live.sessions.map(\.status) == [.unknown])
        #expect(live.sessions.first?.workingDirectory == "/Users/you/Projects/api")
    }

    @Test func unreadableDatabaseGivesDiagnostic() async throws {
        let root = try makeRoot([], database: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not sqlite".utf8).write(to: root.appendingPathComponent("state_5.sqlite"))
        let result = await CodexAdapter(codexRoot: root, processes: FakeProcesses(list: []), now: { now }).refresh()
        #expect(result.sessions.isEmpty)
        #expect(result.diagnostics.count == 1)
    }

    @Test func rolloutTailReaderNeedsMoreDataWhenWindowHasNoEvent() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("rollout-working.jsonl"))
        let lines = data.split(separator: UInt8(ascii: "\n"))
        // Only the last two lines: no status event in the window, so the reader asks for more.
        #expect(CodexRolloutReader.status(lines: Array(lines.suffix(2)), readWholeFile: false) == nil)
        #expect(CodexRolloutReader.status(lines: [], readWholeFile: true)?.status == .unknown)
        // A small tail size still finds the event by growing the window.
        let reader = CodexRolloutReader(tailSizes: [64, 1024 * 1024])
        #expect(reader.read(fixtures.appendingPathComponent("rollout-working.jsonl")).status == .working)
    }

    @Test func codexAdapterIsDeterministic() async throws {
        let rows = [Row(id: fakeID(13), cwd: "/Users/you/Projects/api", rollout: "rollout-idle.jsonl", updated: now)]
        let root = try makeRoot(rows)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = CodexAdapter(codexRoot: root, processes: FakeProcesses(list: [tui(1, "/Users/you/Projects/api")]),
                                   now: { now })
        let first = await adapter.refresh()
        let second = await adapter.refresh()
        #expect(first == second)
    }
}

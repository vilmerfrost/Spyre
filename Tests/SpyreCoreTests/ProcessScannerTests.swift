import Foundation
import os
import Testing
@testable import SpyreCore

/// The one process scanner fake. Both adapter test files use it. All paths are fake.
final class FakeProcessScanner: ProcessScanner {
    private let state = OSAllocatedUnfairLock(initialState: (list: [ScannedProcess](), cwds: [Int32: String]()))

    init(_ list: [ScannedProcess] = [], cwds: [Int32: String] = [:]) { set(list, cwds: cwds) }

    func set(_ list: [ScannedProcess], cwds: [Int32: String] = [:]) { state.withLock { $0 = (list, cwds) } }
    func processes() -> [ScannedProcess] { state.withLock { $0.list } }
    func isAlive(_ pid: Int32) -> Bool { state.withLock { $0.list.contains { $0.pid == pid } } }
    func workingDirectory(of pid: Int32) -> String? { state.withLock { $0.cwds[pid] } }
}

@Suite(.timeLimit(.minutes(1)))
struct ProcessScannerTests {
    @Test func systemScannerSeesThisProcess() throws {
        let scanner = SystemProcessScanner()
        let pid = getpid()
        let me = try #require(scanner.processes().first { $0.pid == pid })
        #expect(me.parentPID == getppid())
        #expect(!me.executablePath.isEmpty)
        #expect(me.startTime != nil)
        #expect(scanner.isAlive(pid))
        #expect(scanner.workingDirectory(of: pid) != nil)
    }

    @Test func systemScannerHandlesDeadPID() {
        let scanner = SystemProcessScanner()
        // PIDs on macOS stay below 100 000, so this PID never exists.
        #expect(!scanner.isAlive(999_999))
        #expect(scanner.workingDirectory(of: 999_999) == nil)
    }

    @Test func oneFakeServesBothAdapters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spyre-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = FakeProcessScanner()
        scanner.set([
            ScannedProcess(pid: 1, parentPID: 0, executablePath: "/opt/homebrew/bin/codex",
                           hasControllingTerminal: true),
            ScannedProcess(pid: 2, parentPID: 0, executablePath: "/Users/you/.local/share/claude/versions/2.1.295"),
        ], cwds: [1: "/Users/you/Projects/api", 2: "/Users/you/Projects/web"])
        let codex = await CodexAdapter(codexRoot: root, processes: scanner).refresh()
        let claude = await ClaudeCodeAdapter(claudeRoot: root, processes: scanner).refresh()
        // Codex sees only its terminal process. Claude sees only its own binary, as a child candidate.
        #expect(codex.sessions.map(\.workingDirectory) == ["/Users/you/Projects/api"])
        #expect(claude.diagnostics.map(\.message) == ["process 2 has no transcript; not shown"])
    }
}

import Foundation
import Testing
@testable import SpyreCore

// All paths, IDs, and process IDs are fake.

private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// A fake process tree: parent links and the set of regular app processes.
private struct FakeTree: ProcessTree {
    var parents: [Int32: Int32]
    var apps: Set<Int32> = []

    func parent(of pid: Int32) -> Int32? { parents[pid] }
    func isRegularApp(_ pid: Int32) -> Bool { apps.contains(pid) }
}

private func session(
    _ id: String = "00000000-0000-0000-0000-0000000000a1", pid: Int32? = 500, host: SessionHost? = .cli,
    cwd: String = "/Users/you/Projects/app", status: SessionStatus = .working, agent: AgentType = .claudeCode
) -> SessionRecord {
    SessionRecord(id: id, agent: agent, workingDirectory: cwd, status: status, lastActivity: now, processID: pid,
                  host: host)
}

@Suite(.timeLimit(.minutes(1)))
struct RowInteractionTests {
    // MARK: Show app (SPEC 4.3)

    @Test func regularAppUpTheChainIsActivated() {
        // claude (500) → shell (400) → login (300) → Terminal (200) → launchd (1)
        let tree = FakeTree(parents: [500: 400, 400: 300, 300: 200, 200: 1], apps: [200])
        #expect(ShowAppResolver.resolve(session(), tree: tree) == .activate(pid: 200))
    }

    @Test func codexTUIActivatesItsTerminal() {
        let tree = FakeTree(parents: [700: 650, 650: 600, 600: 1], apps: [600])
        let codex = session(pid: 700, host: .codex, agent: .codex)
        #expect(ShowAppResolver.resolve(codex, tree: tree) == .activate(pid: 600))
    }

    @Test func desktopRowWalksToTheClaudeAppByDefault() {
        // claude (800) → helper inside the app bundle (790, not regular) → Claude (780)
        let tree = FakeTree(parents: [800: 790, 790: 780, 780: 1], apps: [780])
        let desktop = session(pid: 800, host: .desktop)
        #expect(!ShowAppResolver.desktopDeepLinkVerified)
        #expect(ShowAppResolver.resolve(desktop, tree: tree) == .activate(pid: 780))
    }

    @Test func desktopDeepLinkWhenTurnedOn() {
        let desktop = session("00000000-0000-0000-0000-0000000000d1", pid: nil, host: .desktop)
        let action = ShowAppResolver.resolve(desktop, tree: FakeTree(parents: [:]), useDesktopDeepLink: true)
        #expect(action == .openURL("claude://code/continue?session=00000000-0000-0000-0000-0000000000d1"))
        let cli = session(pid: nil, host: .cli)
        #expect(ShowAppResolver.resolve(cli, tree: FakeTree(parents: [:]), useDesktopDeepLink: true)
            == .openFolder("/Users/you/Projects/app"))
        #expect(ShowAppResolver.desktopDeepLink(sessionID: "") == nil)
        #expect(ShowAppResolver.desktopDeepLink(sessionID: "a b&c") == "claude://code/continue?session=a%20b%26c")
    }

    @Test func noAppFallsBackToTheFolder() {
        // tmux: the server's parent is launchd, so no app is found.
        let tree = FakeTree(parents: [500: 450, 450: 1])
        #expect(ShowAppResolver.resolve(session(), tree: tree) == .openFolder("/Users/you/Projects/app"))
        #expect(ShowAppResolver.resolve(session(pid: nil), tree: tree) == .openFolder("/Users/you/Projects/app"))
        #expect(ShowAppResolver.resolve(session(pid: nil, cwd: ""), tree: tree) == .none)
    }

    @Test func parentLoopAndDeadProcessStop() {
        let loop = FakeTree(parents: [500: 501, 501: 500])
        #expect(ShowAppResolver.firstRegularApp(from: 500, tree: loop) == nil)
        let gone = FakeTree(parents: [:])
        #expect(ShowAppResolver.firstRegularApp(from: 500, tree: gone) == nil)
        let deep = FakeTree(parents: Dictionary(uniqueKeysWithValues: (2...200).map { (Int32($0), Int32($0 - 1)) }),
                            apps: [2])
        #expect(ShowAppResolver.firstRegularApp(from: 200, tree: deep) == nil)
        #expect(ShowAppResolver.firstRegularApp(from: 20, tree: deep) == 2)
    }

    @Test func theSessionProcessItselfCanBeTheApp() {
        #expect(ShowAppResolver.firstRegularApp(from: 42, tree: FakeTree(parents: [:], apps: [42])) == 42)
    }

    // MARK: Host names

    @Test(arguments: [("cli", SessionHost.cli), ("claude-desktop", .desktop), ("claude-vscode", .vscode)])
    func claudeEntrypointMapsToHost(entrypoint: String, host: SessionHost) {
        #expect(SessionHost(claudeEntrypoint: entrypoint) == host)
    }

    @Test func unknownEntrypointHasNoHost() {
        #expect(SessionHost(claudeEntrypoint: nil) == nil)
        #expect(SessionHost(claudeEntrypoint: "sdk-ts") == nil)
    }

    @Test func hostTitles() {
        #expect(SessionHost.allCases.map(\.title) == ["CLI", "Desktop", "VS Code", "Codex", "exec"])
    }

    // MARK: Detail line (SPEC 4.2)

    @Test func detailItemsInOrderWithShortIDAndNoContent() {
        var waiting = session(status: .waiting)
        waiting.waitingReason = "permission prompt"
        waiting.startedAt = now
        let items = waiting.detailItems { _ in "Today 10:00" }
        #expect(items.map(\.label) == ["Path", "Started", "Host", "Waiting reason", "Session ID"])
        #expect(items.map(\.value) == ["/Users/you/Projects/app", "Today 10:00", "CLI", "Permission prompt",
                                       "000000a1"])
        #expect(items.last?.copyValue == waiting.id)
    }

    @Test func agentVersionOnlyForCodex() {
        var codex = session(host: .codex, agent: .codex)
        codex.agentVersion = "0.161.0"
        #expect(codex.detailItems { _ in "" }.last == SessionDetailItem(label: "Agent version", value: "0.161.0"))
        var claude = session()
        claude.agentVersion = "2.1.295"
        #expect(!claude.detailItems { _ in "" }.contains { $0.label == "Agent version" })
    }

    @Test func placeholderIDsAndEmptyPartsAreLeftOut() {
        let starting = SessionRecord(id: "claude-pid-12", agent: .claudeCode, workingDirectory: "", status: .starting,
                                     lastActivity: now)
        #expect(starting.detailItems { _ in "" }.isEmpty)
        let folder = SessionRecord(id: "codex:cwd:/Users/you/x", agent: .codex, workingDirectory: "/Users/you/x",
                                   status: .unknown, lastActivity: now)
        #expect(folder.detailItems { _ in "" }.map(\.label) == ["Path"])
    }

    // MARK: Line 2 parts for the agent mark

    @Test func detailPartsSplitAroundTheAgent() {
        var record = session()
        record.branch = "main"
        record.title = "Fix it"
        let parts = SessionRowText(record, homeDirectory: "/Users/you").detailParts
        #expect(parts.lead == "app · main · ")
        #expect(parts.agentAndMode == "Claude Code")
        record.label = "exec"
        record.branch = nil
        record.title = nil
        let exec = SessionRowText(record, homeDirectory: "/Users/you").detailParts
        #expect(exec.lead == "")
        #expect(exec.agentAndMode == "Claude Code · exec")
    }

    // MARK: Hover freeze (SPEC 4.2)

    @Test func frozenOrderKeepsRowsInPlace() throws {
        let old = [
            SessionRecord(id: "a", agent: .claudeCode, workingDirectory: "/a", status: .working,
                          lastActivity: now.addingTimeInterval(-10)),
            SessionRecord(id: "b", agent: .claudeCode, workingDirectory: "/b", status: .working,
                          lastActivity: now.addingTimeInterval(-20)),
        ]
        let before = old.sections()
        var next = old
        next[1].lastActivity = now          // b is now newer: it would move to the top
        next[0].status = .waiting           // a now needs you: it would move to another group
        next.append(SessionRecord(id: "c", agent: .claudeCode, workingDirectory: "/c", status: .working,
                                  lastActivity: now))
        let frozen = next.sections().frozen(to: before)
        let working = try #require(frozen.first { $0.group == .working })
        #expect(working.rows.map(\.id) == ["a", "b", "c"])
        #expect(working.rows.first?.session.status == .waiting)
        #expect(frozen.map(\.group) == [.working])

        let gone = [next[1]].sections().frozen(to: before)
        #expect(gone.flatMap(\.rows).map(\.id) == ["b"])
    }

    @Test func frozenOrderPutsNewRowsInTheirOwnGroup() {
        let before = [SessionRecord(id: "a", agent: .claudeCode, workingDirectory: "/a", status: .working,
                                    lastActivity: now)].sections()
        let next = [
            SessionRecord(id: "a", agent: .claudeCode, workingDirectory: "/a", status: .working, lastActivity: now),
            SessionRecord(id: "w", agent: .claudeCode, workingDirectory: "/w", status: .waiting, lastActivity: now),
        ]
        let frozen = next.sections().frozen(to: before)
        #expect(frozen.map(\.group) == [.waiting, .working])
    }
}

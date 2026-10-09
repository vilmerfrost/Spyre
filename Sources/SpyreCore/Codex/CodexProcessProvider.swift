import Darwin
import Foundation

/// One process whose executable is named `codex`. `SPEC.md` 5.2 C.
public struct CodexProcess: Sendable, Equatable {
    public var pid: Int32
    public var executablePath: String
    /// The current working directory, or `nil` when Spyre cannot read it.
    public var workingDirectory: String?
    /// `true` when the process has a controlling terminal.
    public var hasControllingTerminal: Bool

    public init(pid: Int32, executablePath: String, workingDirectory: String?, hasControllingTerminal: Bool) {
        self.pid = pid
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.hasControllingTerminal = hasControllingTerminal
    }

    /// `true` when this process is a Codex terminal UI (TUI), not a server.
    ///
    /// The `app-server`, `app-server-daemon`, and `exec-server` processes run detached or under the
    /// ChatGPT app, so they have no controlling terminal. A TUI always has one.
    /// Spyre does not read process arguments: on macOS they come in one buffer with the environment.
    public var isTerminalUI: Bool {
        URL(fileURLWithPath: executablePath).lastPathComponent == "codex"
            && hasControllingTerminal
            && workingDirectory != nil
    }
}

/// Lists `codex` processes. The app injects the system provider. Tests inject a fake.
public protocol CodexProcessProvider: Sendable {
    func codexProcesses() -> [CodexProcess]
}

/// Reads the process table with `libproc`. Reads no arguments and no environment variables.
public struct SystemCodexProcessProvider: CodexProcessProvider {
    public init() {}

    public func codexProcesses() -> [CodexProcess] {
        allPIDs().compactMap { pid in
            guard let path = executablePath(pid), URL(fileURLWithPath: path).lastPathComponent == "codex" else {
                return nil
            }
            return CodexProcess(
                pid: pid,
                executablePath: path,
                workingDirectory: workingDirectory(pid),
                hasControllingTerminal: hasControllingTerminal(pid)
            )
        }
    }

    private func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Leave room for processes that start between the two calls.
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let size = Int32(pids.count * MemoryLayout<Int32>.size)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, size) }
        guard found > 0 else { return [] }
        return pids.prefix(Int(found)).filter { $0 > 0 }
    }

    private func executablePath(_ pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    private func hasControllingTerminal(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_flags & UInt32(PROC_FLAG_CONTROLT) != 0
    }
}

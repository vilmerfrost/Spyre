import Darwin
import Foundation

/// One process from the process list. Holds no arguments and no environment.
public struct ClaudeProcess: Sendable, Equatable {
    public var pid: Int32
    public var parentPID: Int32
    public var executablePath: String
    public var startTime: Date?

    public init(pid: Int32, parentPID: Int32, executablePath: String, startTime: Date? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.executablePath = executablePath
        self.startTime = startTime
    }

    /// `SPEC.md` 5.1 D: match on the executable path, never on the process name.
    public var isClaudeCode: Bool {
        if executablePath.hasSuffix("/claude") { return true }
        guard let range = executablePath.range(of: "/.local/share/claude/versions/") else { return false }
        let version = executablePath[range.upperBound...]
        return !version.isEmpty && !version.contains("/")
    }
}

/// Process access for `ClaudeCodeAdapter`. The app injects the system provider. Tests inject a fake.
public protocol ClaudeProcessProvider: Sendable {
    /// All processes the current user can see.
    func processes() -> [ClaudeProcess]
    /// `kill(pid, 0)` liveness check. Never sends a real signal.
    func isAlive(_ pid: Int32) -> Bool
    /// The current working directory of a process, or `nil` when it cannot be read.
    func workingDirectory(of pid: Int32) -> String?
}

/// The real provider. Uses `sysctl` and `libproc`. Never reads arguments or environment variables.
public struct SystemClaudeProcessProvider: ClaudeProcessProvider {
    public init() {}

    public func processes() -> [ClaudeProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var infos = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 16)
        size = infos.count * stride
        guard sysctl(&mib, 4, &infos, &size, nil, 0) == 0 else { return [] }
        return infos.prefix(size / stride).compactMap { info in
            let pid = info.kp_proc.p_pid
            guard pid > 0, let path = executablePath(of: pid) else { return nil }
            let start = info.kp_proc.p_un.__p_starttime
            return ClaudeProcess(
                pid: pid,
                parentPID: info.kp_eproc.e_ppid,
                executablePath: path,
                startTime: Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
            )
        }
    }

    public func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    private func executablePath(of pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}

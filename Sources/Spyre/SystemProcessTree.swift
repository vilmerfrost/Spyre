import AppKit
import Darwin
import SpyreCore

/// The real process tree for "Show app". Reads the parent PID with `proc_pidinfo` and app facts with
/// `NSRunningApplication`. Never reads process arguments or environment variables. `SPEC.md` 4.3.
struct SystemProcessTree: ProcessTree {
    func parent(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(bitPattern: info.pbi_ppid)
    }

    func isRegularApp(_ pid: Int32) -> Bool {
        MainActor.assumeIsolated {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
            return app.activationPolicy == .regular && app.bundleURL?.pathExtension == "app"
        }
    }
}

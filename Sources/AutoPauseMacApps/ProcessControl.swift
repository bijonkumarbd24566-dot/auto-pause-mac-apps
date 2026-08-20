import Foundation
import Darwin

/// Low-level process control: tree enumeration, memory footprint, SIGSTOP/SIGCONT.
enum ProcessControl {

    /// All pids in the process tree rooted at `root` (root included), breadth-first.
    static func processTree(root: pid_t) -> [pid_t] {
        var result: [pid_t] = [root]
        var queue: [pid_t] = [root]
        var seen: Set<pid_t> = [root]
        while let pid = queue.popLast() {
            for child in children(of: pid) where !seen.contains(child) {
                seen.insert(child)
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }

    /// Direct children of a pid via proc_listchildpids, growing the buffer as needed.
    private static func children(of pid: pid_t) -> [pid_t] {
        var capacity = 64
        while true {
            var buf = [pid_t](repeating: 0, count: capacity)
            let bytes = Int32(capacity * MemoryLayout<pid_t>.size)
            let n = proc_listchildpids(pid, &buf, bytes)
            if n < 0 { return [] }
            let count = Int(n)
            if count < capacity {
                return Array(buf.prefix(count)).filter { $0 > 0 }
            }
            capacity *= 2 // buffer may have been full; retry larger
        }
    }

    /// Memory for a single process.
    ///
    /// `resident` is RAM actually held right now. `footprint` is Activity Monitor's
    /// "Memory" column, which also counts pages already compressed or swapped to disk —
    /// so footprint barely moves when a frozen app's pages are reclaimed, while resident
    /// drops sharply. Both come from one syscall.
    struct MemoryInfo {
        var resident: UInt64 = 0
        var footprint: UInt64 = 0
    }

    static func memoryInfo(of pid: pid_t) -> MemoryInfo {
        var info = rusage_info_current()
        let ok = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard ok == 0 else { return MemoryInfo() }
        return MemoryInfo(resident: info.ri_resident_size, footprint: info.ri_phys_footprint)
    }

    /// Summed memory over the whole process tree.
    static func treeMemory(root: pid_t) -> MemoryInfo {
        processTree(root: root).reduce(into: MemoryInfo()) { acc, pid in
            let m = memoryInfo(of: pid)
            acc.resident += m.resident
            acc.footprint += m.footprint
        }
    }

    /// True if the process is currently stopped (SIGSTOP'd), via BSD process status.
    static func isStopped(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard n == size else { return false }
        return info.pbi_status == UInt32(SSTOP)
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Suspend the whole tree. Parent first so it cannot spawn new children mid-freeze,
    /// then re-enumerate and stop descendants.
    @discardableResult
    static func pauseTree(root: pid_t) -> Bool {
        guard kill(root, SIGSTOP) == 0 else { return false }
        for pid in processTree(root: root) where pid != root {
            kill(pid, SIGSTOP)
        }
        return true
    }

    /// Resume the whole tree. Children first, parent last.
    @discardableResult
    static func resumeTree(root: pid_t) -> Bool {
        let tree = processTree(root: root)
        for pid in tree.reversed() where pid != root {
            kill(pid, SIGCONT)
        }
        return kill(root, SIGCONT) == 0
    }
}

// MARK: - System-wide process enumeration

extension ProcessControl {

    struct ProcInfo {
        let pid: pid_t
        let ppid: pid_t
        let uid: uid_t
        let name: String
        let path: String
    }

    /// Processes owned by the current user. We deliberately ignore other users' and root's
    /// processes: without root we couldn't signal them anyway, so this is both a practical
    /// and a safety boundary.
    static func userProcesses() -> [ProcInfo] {
        let myUID = getuid()
        var capacity = 4096
        var pids: [pid_t] = []

        while true {
            var buf = [pid_t](repeating: 0, count: capacity)
            let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buf,
                                      Int32(capacity * MemoryLayout<pid_t>.size))
            guard bytes > 0 else { return [] }
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            if count < capacity {
                pids = Array(buf.prefix(count)).filter { $0 > 0 }
                break
            }
            capacity *= 2
        }

        return pids.compactMap { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            guard info.pbi_uid == myUID else { return nil }

            let pathMax = 4 * 1024 // PROC_PIDPATHINFO_MAXSIZE, not exported to Swift
            var pathBuf = [CChar](repeating: 0, count: pathMax)
            let path = proc_pidpath(pid, &pathBuf, UInt32(pathMax)) > 0
                ? String(cString: pathBuf) : ""

            let comm = withUnsafePointer(to: info.pbi_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { String(cString: $0) }
            }
            let name = path.isEmpty ? comm : (path as NSString).lastPathComponent

            return ProcInfo(pid: pid, ppid: pid_t(info.pbi_ppid), uid: info.pbi_uid,
                            name: name, path: path)
        }
    }

    /// Processes that must never be signalled — freezing any of these can wedge the UI or
    /// the login session.
    static let protectedNames: Set<String> = [
        // Freezing any of these wedges the UI, the login session, or input handling.
        "WindowServer", "loginwindow", "Finder", "Dock", "SystemUIServer",
        "launchd", "kernel_task", "runningboardd", "logind",
        "ControlCenter", "NotificationCenter", "ControlStrip", "TouchBarServer",
        "NowPlayingTouchUI", "TextInputMenuAgent", "TextInputSwitcher",
        "Spotlight", "talagent", "universalaccessd", "UserEventAgent",
        // Audio, prefs and notification plumbing: freezing these breaks sound and settings.
        "coreaudiod", "audiomxd", "cfprefsd", "distnoted", "pboard",
        // Security and identity: freezing these can lock you out of keychain prompts.
        "securityd", "trustd", "opendirectoryd", "secd", "authd",
        // Window management / accessibility bridges.
        "AccessibilityUIServer", "axassetsd", "StatusBarAgent"
    ]

    static func isProtected(_ info: ProcInfo) -> Bool {
        if info.pid <= 1 { return true }
        if info.pid == ProcessInfo.processInfo.processIdentifier { return true }
        return protectedNames.contains(info.name)
    }
}

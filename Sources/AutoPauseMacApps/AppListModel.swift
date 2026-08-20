import AppKit
import Combine
import Foundation

enum AppState: Equatable {
    case running
    case paused    // SIGSTOP'd: alive, frozen, instantly resumable
    case sleeping  // quit with state preserved: 100% of RAM and swap released
}

enum EntryKind: Equatable {
    case app       // a regular Dock app: can be paused or deep-slept
    case service   // a background helper/daemon: can be frozen, never quit
}

struct AppEntry: Identifiable, Equatable {
    let id: String            // pid for live apps, bundleID for sleeping ones
    let pid: pid_t?           // nil once sleeping
    let name: String
    let bundleID: String?
    let icon: NSImage?
    let resident: UInt64      // RAM actually held right now
    let footprint: UInt64     // incl. compressed + swapped pages
    let reclaimedBytes: UInt64
    let state: AppState
    let launchDate: Date?
    let history: [UInt64]
    var kind: EntryKind = .app

    /// Services are frozen only — quitting a daemon can break sync, backups or system
    /// features, and it has no state-restoration contract to bring it back.
    var canDeepSleep: Bool { kind == .app && state != .sleeping }
}

@MainActor
final class AppListModel: ObservableObject {
    @Published var entries: [AppEntry] = []
    @Published var pausedCount: Int = 0
    @Published var totalMemory: UInt64 = UInt64(ProcessInfo.processInfo.physicalMemory)
    @Published var usedMemory: UInt64 = 0
    @Published var systemStats: SystemStats = .current()
    @Published var systemHistory: [UInt64] = []
    /// Transient message shown in the panel, e.g. when an app refuses to sleep.
    @Published var notice: String?
    @Published var showServices = true
    /// Everything suspended by the last Local Model Mode run, so it can be undone exactly.
    @Published var reclaimSession: [pid_t] = []

    /// Rolling per-app resident samples for the sparklines. ~40 samples at 3s ≈ 2 minutes.
    private var history: [pid_t: [UInt64]] = [:]
    private let historyLimit = 40

    /// Footprint captured at the moment an app was frozen, so we can show what was reclaimed.
    private var footprintAtPause: [pid_t: UInt64] = [:]

    /// Last time each app was frontmost, for idle-based auto-pause.
    private var lastFrontDate: [pid_t: Date] = [:]

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for note in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: note, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                             object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.lastFrontDate[app.processIdentifier] = Date() }
        })
        refresh()
    }

    func startRefreshing() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func runningApp(for entry: AppEntry) -> NSRunningApplication? {
        guard let pid = entry.pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    func refresh() {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != ownPid
                && $0.bundleIdentifier != "com.apple.finder"
        }

        PausedStore.shared.pruneStale(currentApps: apps.map { ($0.processIdentifier, $0.launchDate) })
        SleptStore.shared.prune(runningBundleIDs: Set(apps.compactMap(\.bundleIdentifier)))

        let livePids = Set(apps.map(\.processIdentifier))
        history = history.filter { livePids.contains($0.key) }
        lastFrontDate = lastFrontDate.filter { livePids.contains($0.key) }
        footprintAtPause = footprintAtPause.filter { livePids.contains($0.key) }

        var newEntries: [AppEntry] = []

        for app in apps {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }

            var paused = ProcessControl.isStopped(pid) || PausedStore.shared.contains(pid: pid)
            let mem = ProcessControl.treeMemory(root: pid)

            if !paused {
                var samples = history[pid] ?? []
                samples.append(mem.resident)
                if samples.count > historyLimit { samples.removeFirst(samples.count - historyLimit) }
                history[pid] = samples

                if lastFrontDate[pid] == nil { lastFrontDate[pid] = app.launchDate ?? Date() }
                if shouldAutoPause(app: app, pid: pid) {
                    footprintAtPause[pid] = mem.footprint
                    ProcessControl.pauseTree(root: pid)
                    PausedStore.shared.add(PausedRecord(
                        pid: pid, bundleID: app.bundleIdentifier,
                        name: app.localizedName ?? "Unknown", launchDate: app.launchDate))
                    paused = true
                }
            }

            // Everything the frozen app has handed back since it was frozen.
            let reclaimed = paused
                ? (footprintAtPause[pid].map { $0 > mem.resident ? $0 - mem.resident : 0 } ?? 0)
                : 0

            newEntries.append(AppEntry(
                id: String(pid),
                pid: pid,
                name: app.localizedName ?? "Unknown",
                bundleID: app.bundleIdentifier,
                icon: app.icon,
                resident: mem.resident,
                footprint: mem.footprint,
                reclaimedBytes: reclaimed,
                state: paused ? .paused : .running,
                launchDate: app.launchDate,
                history: history[pid] ?? []
            ))
        }

        if showServices {
            newEntries.append(contentsOf: serviceEntries(excluding: apps))
        }

        // Sleeping apps are no longer processes; surface them from the store.
        for rec in SleptStore.shared.records {
            newEntries.append(AppEntry(
                id: rec.bundleID,
                pid: nil,
                name: rec.name,
                bundleID: rec.bundleID,
                icon: rec.icon,
                resident: 0,
                footprint: 0,
                reclaimedBytes: rec.reclaimedBytes,
                state: .sleeping,
                launchDate: nil,
                history: []
            ))
        }

        // Suspended apps pin to the top: they hold 0 resident RAM, so sorting purely by
        // memory buried them under every running app and made them hard to bring back.
        // Running apps below, heaviest first.
        entries = newEntries.sorted { lhs, rhs in
            let lSuspended = lhs.state != .running
            let rSuspended = rhs.state != .running
            if lSuspended != rSuspended { return lSuspended }
            if lSuspended && rSuspended {
                // Sleeping before merely frozen; then by how much each gave back.
                if (lhs.state == .sleeping) != (rhs.state == .sleeping) { return lhs.state == .sleeping }
                return lhs.reclaimedBytes > rhs.reclaimedBytes
            }
            return lhs.resident > rhs.resident
        }
        pausedCount = entries.filter { $0.state != .running }.count

        let stats = SystemStats.current()
        systemStats = stats
        usedMemory = stats.usedBytes
        systemHistory.append(stats.usedBytes)
        if systemHistory.count > historyLimit { systemHistory.removeFirst(systemHistory.count - historyLimit) }
    }

    /// Background processes that aren't part of any Dock app: dev servers, sync daemons,
    /// updater helpers. Grouped by their top-level ancestor so one row covers a whole
    /// service rather than a dozen unlabelled child pids.
    private func serviceEntries(excluding apps: [NSRunningApplication]) -> [AppEntry] {
        let procs = ProcessControl.userProcesses()
        let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        var appPids = Set<pid_t>()
        for app in apps {
            for pid in ProcessControl.processTree(root: app.processIdentifier) { appPids.insert(pid) }
        }
        let ownPid = ProcessInfo.processInfo.processIdentifier

        func rootAncestor(_ info: ProcessControl.ProcInfo) -> ProcessControl.ProcInfo {
            var cur = info, hops = 0
            while cur.ppid > 1, let parent = byPid[cur.ppid], hops < 64 { cur = parent; hops += 1 }
            return cur
        }

        struct Group { var info: ProcessControl.ProcInfo; var resident: UInt64 = 0
                       var footprint: UInt64 = 0; var pids: [pid_t] = [] }
        var groups: [pid_t: Group] = [:]

        for proc in procs where !appPids.contains(proc.pid) && proc.pid != ownPid {
            let root = rootAncestor(proc)
            if ProcessControl.isProtected(root) || root.pid == ownPid { continue }
            let mem = ProcessControl.memoryInfo(of: proc.pid)
            var group = groups[root.pid] ?? Group(info: root)
            group.resident += mem.resident
            group.footprint += mem.footprint
            group.pids.append(proc.pid)
            groups[root.pid] = group
        }

        // Below ~25 MB a service isn't worth a row or the risk of freezing it.
        let threshold: UInt64 = 25 * 1024 * 1024
        return groups.values
            .filter { $0.resident >= threshold }
            .sorted { $0.resident > $1.resident }
            .prefix(40)
            .map { group in
                let pid = group.info.pid
                let frozen = ProcessControl.isStopped(pid)
                var samples = history[pid] ?? []
                if !frozen {
                    samples.append(group.resident)
                    if samples.count > historyLimit { samples.removeFirst(samples.count - historyLimit) }
                    history[pid] = samples
                }
                return AppEntry(
                    id: "svc-\(pid)",
                    pid: pid,
                    name: group.info.name,
                    bundleID: nil,
                    icon: nil,
                    resident: group.resident,
                    footprint: group.footprint,
                    reclaimedBytes: frozen
                        ? (footprintAtPause[pid].map { $0 > group.resident ? $0 - group.resident : 0 } ?? 0)
                        : 0,
                    state: frozen ? .paused : .running,
                    launchDate: nil,
                    history: samples,
                    kind: .service)
            }
    }

    // MARK: - Local Model Mode

    /// Suspend background apps and services, heaviest first, until `targetBytes` of RAM has
    /// been handed back — for freeing headroom to run a local model. Never touches the
    /// frontmost app, protected processes, or anything already suspended.
    func reclaim(targetBytes: UInt64) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var freed: UInt64 = 0
        var touched: [pid_t] = []

        let candidates = entries
            .filter { $0.state == .running && $0.pid != nil && $0.pid != frontmost }
            .sorted { $0.resident > $1.resident }

        for entry in candidates {
            guard freed < targetBytes, let pid = entry.pid else { break }
            footprintAtPause[pid] = entry.footprint
            guard ProcessControl.pauseTree(root: pid) else { continue }
            if entry.kind == .app {
                PausedStore.shared.add(PausedRecord(
                    pid: pid, bundleID: entry.bundleID, name: entry.name, launchDate: entry.launchDate))
            }
            freed += entry.resident
            touched.append(pid)
        }

        reclaimSession = touched
        notice = touched.isEmpty
            ? "Nothing left to suspend — everything is already frozen or protected."
            : "Froze \(touched.count) items, reclaiming about \(MenuView.fmt(freed))."
        refresh()
    }

    /// Undo exactly what the last reclaim froze, leaving anything you froze by hand alone.
    func restoreReclaimSession() {
        for pid in reclaimSession {
            ProcessControl.resumeTree(root: pid)
            PausedStore.shared.remove(pid: pid)
            footprintAtPause[pid] = nil
        }
        notice = "Restored \(reclaimSession.count) items."
        reclaimSession = []
        refresh()
    }

    /// How much a reclaim could free right now, for the target slider's estimate.
    var reclaimableBytes: UInt64 {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return entries
            .filter { $0.state == .running && $0.pid != nil && $0.pid != frontmost }
            .reduce(0) { $0 + $1.resident }
    }

    private func shouldAutoPause(app: NSRunningApplication, pid: pid_t) -> Bool {
        let settings = AppSettingsStore.shared.settings(for: app.bundleIdentifier)
        guard settings.autoPauseEnabled, !app.isActive else { return false }
        guard let since = lastFrontDate[pid] else { return false }
        return Date().timeIntervalSince(since) > TimeInterval(settings.autoPauseMinutes * 60)
    }

    // MARK: - Actions

    func pause(_ entry: AppEntry) {
        guard let pid = entry.pid else { return }
        footprintAtPause[pid] = entry.footprint
        guard ProcessControl.pauseTree(root: pid) else { return }
        PausedStore.shared.add(PausedRecord(
            pid: pid, bundleID: entry.bundleID, name: entry.name, launchDate: entry.launchDate))
        refresh()
    }

    func resume(_ entry: AppEntry) {
        if entry.state == .sleeping {
            wake(entry)
            return
        }
        guard let pid = entry.pid else { return }
        ProcessControl.resumeTree(root: pid)
        PausedStore.shared.remove(pid: pid)
        footprintAtPause[pid] = nil
        lastFrontDate[pid] = Date()
        refresh()
    }

    func deepSleep(_ entry: AppEntry) {
        guard let app = runningApp(for: entry), let pid = entry.pid else { return }
        let footprint = entry.footprint
        Task { @MainActor in
            let result = await DeepSleepController.sleep(app: app, name: entry.name, footprint: footprint)
            switch result {
            case .slept:
                PausedStore.shared.remove(pid: pid)
                footprintAtPause[pid] = nil
            case .refused:
                // Almost always an unsaved-work save sheet. Leave it frozen instead.
                notice = "\(entry.name) has unsaved work, so it was left frozen instead of quit."
                footprintAtPause[pid] = footprint
                ProcessControl.pauseTree(root: pid)
                PausedStore.shared.add(PausedRecord(
                    pid: pid, bundleID: entry.bundleID, name: entry.name, launchDate: entry.launchDate))
            case .failed(let message):
                notice = "\(entry.name): \(message)"
            }
            refresh()
        }
    }

    func wake(_ entry: AppEntry) {
        guard let rec = SleptStore.shared.records.first(where: { $0.bundleID == entry.id }) else { return }
        Task { @MainActor in
            switch await DeepSleepController.wake(rec) {
            case .success:
                notice = nil
            case .failure(let error):
                notice = "Couldn't wake \(rec.name): \(error.localizedDescription). It's still listed — try again."
            }
            refresh()
        }
    }

    func resumeAll() {
        for rec in PausedStore.shared.records {
            ProcessControl.resumeTree(root: rec.pid)
            PausedStore.shared.remove(pid: rec.pid)
        }
        for entry in entries where entry.state == .paused {
            if let pid = entry.pid { ProcessControl.resumeTree(root: pid) }
        }
        let sleeping = SleptStore.shared.records
        Task { @MainActor in
            for rec in sleeping { _ = await DeepSleepController.wake(rec) }
            refresh()
        }
        refresh()
    }
}

import Foundation

/// Persists which apps are paused so a crash of Pause never strands frozen apps.
struct PausedRecord: Codable, Equatable {
    let pid: pid_t
    let bundleID: String?
    let name: String
    let launchDate: Date?
}

final class PausedStore {
    static let shared = PausedStore()

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pause", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("paused.json")
    }()

    private(set) var records: [PausedRecord] = []

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PausedRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func add(_ record: PausedRecord) {
        records.removeAll { $0.pid == record.pid }
        records.append(record)
        save()
    }

    func remove(pid: pid_t) {
        records.removeAll { $0.pid == pid }
        save()
    }

    func contains(pid: pid_t) -> Bool {
        records.contains { $0.pid == pid }
    }

    /// Drop records whose process is gone or was replaced (pid reuse guard via launch date).
    func pruneStale(currentApps: [(pid: pid_t, launchDate: Date?)]) {
        let live = Dictionary(uniqueKeysWithValues: currentApps.map { ($0.pid, $0.launchDate) })
        records.removeAll { rec in
            guard let launch = live[rec.pid] else { return true } // process gone
            if let recDate = rec.launchDate, let nowDate = launch ?? nil {
                return abs(recDate.timeIntervalSince(nowDate)) > 2 // different process reusing pid
            }
            return false
        }
        save()
    }
}

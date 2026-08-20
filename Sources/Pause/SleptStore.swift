import AppKit
import Foundation

/// A deep-slept app. It is no longer a running process, so this record is the only way
/// it stays visible and wakeable — without it, the app would vanish from the list.
struct SleptRecord: Codable, Equatable, Identifiable {
    let bundleID: String
    let bundlePath: String
    let name: String
    let sleptAt: Date
    let reclaimedBytes: UInt64

    var id: String { bundleID }

    var icon: NSImage? {
        guard FileManager.default.fileExists(atPath: bundlePath) else { return nil }
        return NSWorkspace.shared.icon(forFile: bundlePath)
    }
}

final class SleptStore {
    static let shared = SleptStore()

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pause", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("slept.json")
    }()

    private(set) var records: [SleptRecord] = []

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SleptRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func add(_ record: SleptRecord) {
        records.removeAll { $0.bundleID == record.bundleID }
        records.append(record)
        save()
    }

    func remove(bundleID: String) {
        records.removeAll { $0.bundleID == bundleID }
        save()
    }

    /// Drop records for apps the user relaunched themselves, and for deleted bundles.
    func prune(runningBundleIDs: Set<String>) {
        let before = records.count
        records.removeAll { rec in
            runningBundleIDs.contains(rec.bundleID)
                || !FileManager.default.fileExists(atPath: rec.bundlePath)
        }
        if records.count != before { save() }
    }
}

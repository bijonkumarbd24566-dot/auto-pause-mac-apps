import Foundation

/// Per-app preferences (currently: idle-based auto-pause), keyed by bundle identifier.
struct AppSettings: Codable, Equatable {
    var bundleID: String
    var autoPauseEnabled: Bool = false
    var autoPauseMinutes: Int = 10
}

/// Global, one-off flags.
enum PauseFlags {
    private static let seenDeepSleepWarningKey = "PauseHasSeenDeepSleepWarning"

    static var hasSeenDeepSleepWarning: Bool {
        get { UserDefaults.standard.bool(forKey: seenDeepSleepWarningKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenDeepSleepWarningKey) }
    }
}

final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pause", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    private var byBundle: [String: AppSettings] = [:]

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AppSettings].self, from: data) else { return }
        byBundle = Dictionary(uniqueKeysWithValues: decoded.map { ($0.bundleID, $0) })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(byBundle.values)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func settings(for bundleID: String?) -> AppSettings {
        guard let id = bundleID, let existing = byBundle[id] else {
            return AppSettings(bundleID: bundleID ?? "")
        }
        return existing
    }

    func update(_ settings: AppSettings) {
        guard !settings.bundleID.isEmpty else { return }
        byBundle[settings.bundleID] = settings
        save()
    }
}

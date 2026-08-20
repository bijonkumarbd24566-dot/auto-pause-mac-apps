import Foundation
import ServiceManagement

/// Start Auto Pause Mac Apps automatically when you log in.
///
/// Uses `SMAppService` (macOS 13+), which registers the app with the modern login-items
/// system — the same list shown in System Settings ▸ General ▸ Login Items. No helper
/// bundle and no deprecated `LSSharedFileList` shimming required.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has switched this off in System Settings rather than in our UI —
    /// we can't re-enable it programmatically in that case, so the UI must say so.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                // Registering while already enabled throws, so make it idempotent.
                guard SMAppService.mainApp.status != .enabled else { return .success(()) }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            // register() can succeed while the item still needs approval, or silently not
            // take effect when the app is running from somewhere unusual (a DMG, Downloads,
            // a build folder). Read the status back rather than assume it worked.
            let status = SMAppService.mainApp.status
            if enabled && status != .enabled {
                if status == .requiresApproval {
                    return .failure(LoginError.needsApproval)
                }
                return .failure(LoginError.didNotStick)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    enum LoginError: LocalizedError {
        case needsApproval
        case didNotStick

        var errorDescription: String? {
            switch self {
            case .needsApproval:
                return "macOS needs you to approve this in System Settings ▸ General ▸ Login Items."
            case .didNotStick:
                return "Move the app to your Applications folder first, then try again."
            }
        }
    }

    /// Opens System Settings at Login Items, for when approval was revoked there.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

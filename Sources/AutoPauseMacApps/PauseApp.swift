import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Never strand frozen apps: resume everything on quit.
        for rec in PausedStore.shared.records {
            ProcessControl.resumeTree(root: rec.pid)
            PausedStore.shared.remove(pid: rec.pid)
        }
    }
}

@main
struct PauseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppListModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.pausedCount > 0 ? "pause.circle.fill" : "pause.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

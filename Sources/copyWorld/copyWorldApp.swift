import AppKit
import SwiftUI

@main
struct CopyWorldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(appState: AppState.shared)
    }
}

private struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("copyWorld")
                .font(.title2.bold())
            Text("First version: text clipboard history, search, copy back, and local persistence.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360)
    }
}

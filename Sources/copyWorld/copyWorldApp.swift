import AppKit
import SwiftUI

@main
struct CopyWorldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appState = AppState.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            SettingsView(launchAtLoginManager: appState.launchAtLoginManager)
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
    let launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("copyWorld")
                .font(.title2.bold())
            Text("First version: text clipboard history, search, copy back, and local persistence.")
                .foregroundStyle(.secondary)

            Toggle(
                "Launch copyWorld at login",
                isOn: Binding(
                    get: { launchAtLoginManager.isEnabled },
                    set: { launchAtLoginManager.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)

            if let statusMessage = launchAtLoginManager.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            launchAtLoginManager.refresh()
        }
    }
}

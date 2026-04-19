import AppKit
import SwiftUI

@main
struct copyWorldApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("copyWorld", systemImage: "clipboard") {
            MenuBarView(
                historyStore: appState.historyStore,
                monitor: appState.monitor
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
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

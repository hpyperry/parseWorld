import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusMessage = error.localizedDescription
        }
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = nil
        case .requiresApproval:
            isEnabled = false
            statusMessage = String(localized: "Launch at login needs approval in System Settings > General > Login Items.")
        case .notFound:
            isEnabled = false
            statusMessage = String(localized: "Launch at login is unavailable in the current app bundle.")
        case .notRegistered:
            isEnabled = false
            statusMessage = nil
        @unknown default:
            isEnabled = false
            statusMessage = String(localized: "Launch at login status is unavailable.")
        }
    }
}

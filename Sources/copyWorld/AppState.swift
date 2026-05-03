import Foundation

@MainActor
final class AppState {
    static let shared = AppState()

    let storage: ClipboardStorage
    let historyStore: ClipboardHistoryStore
    let monitor: ClipboardMonitor
    let launchAtLoginManager: LaunchAtLoginManager

    private init() {
        let storage = ClipboardStorage(maxItems: 100)
        self.storage = storage

        let historyStore = ClipboardHistoryStore(storage: storage, maximumItems: 100)
        self.historyStore = historyStore

        self.monitor = ClipboardMonitor(historyStore: historyStore, storage: storage)
        self.launchAtLoginManager = LaunchAtLoginManager()
        self.monitor.start()
    }
}

import AppKit
import Foundation

final class FakePasteboard: ClipboardPasteboard {
    private(set) var changeCount: Int = 0
    private var storedString: String?

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        storedString
    }

    @discardableResult
    func clearContents() -> Int {
        storedString = nil
        changeCount += 1
        return changeCount
    }

    @discardableResult
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        storedString = string
        changeCount += 1
        return true
    }

    func simulateExternalCopy(_ text: String) {
        storedString = text
        changeCount += 1
    }
}

@MainActor
func makeStore() -> ClipboardHistoryStore {
    let suiteName = "parseWorld.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return ClipboardHistoryStore(maximumItems: 30, userDefaults: defaults)
}

@MainActor
func runTests() {
    let pasteboard = FakePasteboard()
    let store = makeStore()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store)

    pasteboard.simulateExternalCopy("first external copy")
    monitor.processPendingChange()
    precondition(store.items.first?.text == "first external copy", "External copies should be saved")

    monitor.setCaptureSuspended(true)
    pasteboard.simulateExternalCopy("copied while preview is open")
    monitor.processPendingChange()
    precondition(store.items.first?.text == "first external copy", "Copies while capture is suspended must be ignored")

    monitor.setCaptureSuspended(false)
    pasteboard.simulateExternalCopy("after preview closes")
    monitor.processPendingChange()
    precondition(store.items.first?.text == "after preview closes", "External copies should resume after preview closes")

    let currentCount = store.items.count
    if let item = store.items.first {
        monitor.copy(item)
        monitor.processPendingChange()
        precondition(store.items.count == currentCount, "Copy Back should not duplicate an item")
    } else {
        preconditionFailure("Expected at least one clipboard item after test setup")
    }

    print("PASS: clipboard monitor suspension and copy-back rules work")
}

@main
struct ClipboardMonitorTestRunner {
    static func main() {
        Task { @MainActor in
            runTests()
            exit(EXIT_SUCCESS)
        }

        RunLoop.main.run()
    }
}

import AppKit
import Foundation
import Testing
@testable import copyWorld

// MARK: - Fake pasteboard for testing

private final class FakePasteboard: ClipboardPasteboard {
    private(set) var changeCount: Int = 0
    private var storedString: String?
    private var storedData: [String: Data] = [:]

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        storedString
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        storedData[dataType.rawValue]
    }

    @discardableResult
    func clearContents() -> Int {
        storedString = nil
        storedData.removeAll()
        changeCount += 1
        return changeCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        storedString = string
        changeCount += 1
        return true
    }

    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        if let item = objects.first as? NSPasteboardItem {
            storedString = item.string(forType: .string)
            for type in item.types {
                if let data = item.data(forType: type) {
                    storedData[type.rawValue] = data
                }
            }
        }
        changeCount += 1
        return true
    }

    func simulateExternalCopy(text: String) {
        storedString = text
        storedData.removeAll()
        changeCount += 1
    }

    func simulateExternalCopy(rtfData: Data, plainText: String) {
        storedString = plainText
        storedData[NSPasteboard.PasteboardType.rtf.rawValue] = rtfData
        changeCount += 1
    }

    func simulateExternalCopy(imageData: Data, format: String) {
        storedString = nil
        let type = format == "png" ? NSPasteboard.PasteboardType.png : NSPasteboard.PasteboardType.tiff
        storedData[type.rawValue] = imageData
        changeCount += 1
    }

    func simulateExternalCopy(htmlData: Data, plainText: String) {
        storedString = plainText
        storedData[NSPasteboard.PasteboardType.html.rawValue] = htmlData
        changeCount += 1
    }
}

// MARK: - Helper

@MainActor
private func makeTestStore() -> ClipboardHistoryStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("copyWorldMonitorTest-\(UUID().uuidString)")
    let storage = ClipboardStorage(maxItems: 30, fileManager: .default)
    return ClipboardHistoryStore(storage: storage, maximumItems: 30)
}

private func cleanTestItems() {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("copyWorld/items", isDirectory: true)
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Tests

@MainActor
@Suite(.serialized)
struct ClipboardMonitorTests {

    // MARK: - Text capture

    @Test func capture_text() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        pasteboard.simulateExternalCopy(text: "hello world")
        monitor.processPendingChange()

        #expect(store.items.count == 1)
        #expect(store.items[0].text == "hello world")
        #expect(store.items[0].type == .text)
        cleanTestItems()
    }

    @Test func capture_ignoresEmptyText() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        pasteboard.simulateExternalCopy(text: "   ")
        monitor.processPendingChange()

        #expect(store.items.isEmpty)
        cleanTestItems()
    }

    // MARK: - RTF capture

    @Test func capture_rtf() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        let rtfData = "{\\rtf1 Bold}".data(using: .utf8)!
        pasteboard.simulateExternalCopy(rtfData: rtfData, plainText: "Bold")
        monitor.processPendingChange()

        #expect(store.items.count == 1)
        #expect(store.items[0].type == .rtf)
        #expect(store.items[0].text == "Bold")
        cleanTestItems()
    }

    // MARK: - Image capture

    @Test func capture_image_png() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { $0.fill(); return true }
        let pngData = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        pasteboard.simulateExternalCopy(imageData: pngData, format: "png")
        monitor.processPendingChange()

        #expect(store.items.count == 1)
        #expect(store.items[0].type == .image)
        #expect(store.items[0].imageFormat == "png")
        cleanTestItems()
    }

    // MARK: - Capture suspension

    @Test func captureSuspension_ignoresExternalChanges() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        pasteboard.simulateExternalCopy(text: "before suspend")
        monitor.processPendingChange()
        #expect(store.items.count == 1)

        monitor.setCaptureSuspended(true)
        pasteboard.simulateExternalCopy(text: "while suspended")
        monitor.processPendingChange()
        #expect(store.items.count == 1) // ignored

        monitor.setCaptureSuspended(false)
        pasteboard.simulateExternalCopy(text: "after resume")
        monitor.processPendingChange()
        #expect(store.items.count == 2)
        #expect(store.items[0].text == "after resume")
        cleanTestItems()
    }

    // MARK: - Copy-back dedup

    @Test func copyBack_doesNotReduplicate() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        pasteboard.simulateExternalCopy(text: "original")
        monitor.processPendingChange()

        let count = store.items.count
        if let item = store.items.first {
            monitor.copy(item)
            monitor.processPendingChange()
            #expect(store.items.count == count)
        } else {
            Issue.record("Expected at least one item")
        }
        cleanTestItems()
    }

    // MARK: - Priority (image > RTF > text)

    @Test func capturePriority_imageOverText() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        // Simulate pasteboard having both image and string data
        var item = NSPasteboardItem()
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { $0.fill(); return true }
        item.setData(image.tiffRepresentation!, forType: .tiff)
        item.setString("also present", forType: .string)
        _ = pasteboard.writeObjects([item])
        // writeObjects in our fake sets both string and storedData

        monitor.processPendingChange()
        #expect(store.items.count == 1)
        #expect(store.items[0].type == .image) // image wins
        cleanTestItems()
    }

    // MARK: - Same change count is skipped

    @Test func noChange_skipsProcessing() {
        cleanTestItems()
        let pasteboard = FakePasteboard()
        let store = makeTestStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store, storage: storeTestStorage())

        pasteboard.simulateExternalCopy(text: "first")
        monitor.processPendingChange()

        // Call again without new change — should skip
        monitor.processPendingChange()
        #expect(store.items.count == 1)
        cleanTestItems()
    }
}

// Helper to create a test Storage
@MainActor
private func storeTestStorage() -> ClipboardStorage {
    ClipboardStorage(maxItems: 30, fileManager: .default)
}

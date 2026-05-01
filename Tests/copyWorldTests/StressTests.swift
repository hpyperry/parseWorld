import AppKit
import Foundation
import Testing
@testable import copyWorld

@MainActor
@Suite(.serialized)
struct StressTests {

    private static var itemsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("copyWorld/items", isDirectory: true)
    }

    static func cleanItemsDirectory() throws {
        let url = itemsURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Storage stress

    @Test func saveMaxItems_rapidFire() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)

        for i in 0..<30 {
            let item = ClipboardItem(text: "stress item \(i)")
            try storage.save(item: item, rtfData: nil, imageData: nil)
        }

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 30)
    }

    @Test func prune_exceedMaxByLargeMargin() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 10)

        for i in 0..<100 {
            let item = ClipboardItem(text: "prune item \(i)")
            try storage.save(item: item, rtfData: nil, imageData: nil)
        }

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 10)
        #expect(loaded.first?.text == "prune item 99") // newest first
        #expect(loaded.last?.text == "prune item 90")  // oldest within limit
    }

    @Test func extremePrune_1000items() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)

        for i in 0..<1000 {
            let item = ClipboardItem(text: "bulk \(i)")
            try storage.save(item: item, rtfData: nil, imageData: nil)
        }

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 5)
        #expect(loaded[0].text == "bulk 999")
    }

    // MARK: - Large content

    @Test func largeText_100KB() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 10)

        let chunk = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 2000) // ~88KB
        let item = ClipboardItem(text: chunk)
        try storage.save(item: item, rtfData: nil, imageData: nil)

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 1)
        #expect(loaded[0].contentHash == item.contentHash)
        #expect(loaded[0].text.count == chunk.count)
    }

    @Test func largeText_1MB() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 10)

        let chunk = String(repeating: "A", count: 1_000_000)
        let item = ClipboardItem(text: chunk)
        try storage.save(item: item, rtfData: nil, imageData: nil)

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 1)
        #expect(loaded[0].text.count == 1_000_000)
    }

    @Test func largeImage_4K() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 10)

        let image = NSImage(size: NSSize(width: 3840, height: 2160), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        guard let tiffData = image.tiffRepresentation else {
            Issue.record("Failed to create test image")
            return
        }
        let pngData = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:])
        guard let pngData else {
            Issue.record("Failed to encode PNG")
            return
        }

        let item = ClipboardItem(imageData: pngData, format: "png")
        try storage.save(item: item, rtfData: nil, imageData: pngData)

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 1)
        #expect(loaded[0].type == .image)
        #expect(loaded[0].thumbnail != nil)
    }

    // MARK: - Hash performance

    @Test func sha256_largeDataPerformance() throws {
        let data = Data((0..<10_000_000).map { UInt8($0 & 0xff) }) // 10MB
        let start = Date()
        let hash = ClipboardItem.sha256(data)
        let elapsed = Date().timeIntervalSince(start)

        #expect(!hash.isEmpty)
        #expect(hash.count == 64)
        #expect(elapsed < 1.0) // should hash 10MB well under 1 second
    }

    // MARK: - Dedup stress

    @Test func rapidDedup_sameContentRepeatedly() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)

        for _ in 0..<50 {
            store.save(item: ClipboardItem(text: "same content every time"))
        }

        #expect(store.items.count == 1)
    }

    @Test func dedup_mixedUniqueAndDuplicate() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)

        for i in 0..<20 {
            store.save(item: ClipboardItem(text: "unique \(i)"))
        }
        for _ in 0..<20 {
            store.save(item: ClipboardItem(text: "unique 5")) // duplicate
        }

        #expect(store.items.count == 20)
        #expect(store.items[0].text == "unique 5") // dedup moves to top
    }

    // MARK: - Rapid removal

    @Test func rapidAddRemove_interleaved() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)

        var ids: [UUID] = []
        for i in 0..<30 {
            let item = ClipboardItem(text: "item \(i)")
            try storage.save(item: item, rtfData: nil, imageData: nil)
            ids.append(item.id)
        }

        // Remove every other item
        for i in stride(from: 0, to: ids.count, by: 2) {
            try storage.delete(itemID: ids[i])
        }

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 15)
    }

    @Test func clearAndRepopulate_repeatedly() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)

        for cycle in 0..<5 {
            for i in 0..<10 {
                let item = ClipboardItem(text: "cycle \(cycle) item \(i)")
                try storage.save(item: item, rtfData: nil, imageData: nil)
            }
            #expect(storage.loadAllMetadata().count == min(10, 10))

            try storage.clearAll()
            #expect(storage.loadAllMetadata().isEmpty)
        }
    }

    // MARK: - History store stress

    @Test func historyStore_maxItemsEnforced() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 20)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 20)

        for i in 0..<50 {
            store.save(item: ClipboardItem(text: "hs item \(i)"))
        }
        #expect(store.items.count == 20)
        #expect(store.items[0].text == "hs item 49")
    }

    @Test func historyStore_rapidDedupAndReorder() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)

        store.save(item: ClipboardItem(text: "A"))
        store.save(item: ClipboardItem(text: "B"))
        store.save(item: ClipboardItem(text: "C"))
        store.save(item: ClipboardItem(text: "A")) // should move A to top
        store.save(item: ClipboardItem(text: "B")) // should move B to top

        #expect(store.items.count == 3)
        #expect(store.items[0].text == "B")
        #expect(store.items[1].text == "A")
        #expect(store.items[2].text == "C")
    }

    // MARK: - Monitor stress (simulated pasteboard)

    @Test func monitor_rapidPollingSimulation() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let fakePasteboard = FakePasteboard()
        let monitor = ClipboardMonitor(pasteboard: fakePasteboard, historyStore: store, storage: storage)

        // Simulate 50 rapid clipboard changes
        for i in 0..<50 {
            fakePasteboard.simulateExternalCopy(text: "clipboard change \(i)")
            monitor.processPendingChange()
        }

        #expect(store.items.count == 30)
        #expect(store.items[0].text == "clipboard change 49")
    }

    @Test func monitor_rapidSameContentIgnored() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let fakePasteboard = FakePasteboard()
        let monitor = ClipboardMonitor(pasteboard: fakePasteboard, historyStore: store, storage: storage)

        for _ in 0..<20 {
            fakePasteboard.simulateExternalCopy(text: "same text")
            monitor.processPendingChange()
        }

        #expect(store.items.count == 1)
    }

    @Test func monitor_emptyTextRepeatedlyIgnored() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let fakePasteboard = FakePasteboard()
        let monitor = ClipboardMonitor(pasteboard: fakePasteboard, historyStore: store, storage: storage)

        for _ in 0..<100 {
            fakePasteboard.simulateExternalCopy(text: "   \n  ")
            monitor.processPendingChange()
        }

        #expect(store.items.isEmpty)
    }

    // MARK: - Thumbnail stress

    @Test func thumbnail_manyImages() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 30)

        for size in [100, 200, 400, 800, 1600] {
            let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                NSColor.blue.setFill()
                rect.fill()
                return true
            }
            guard let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                continue
            }
            let item = ClipboardItem(imageData: png, format: "png")
            try storage.save(item: item, rtfData: nil, imageData: png)
        }

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 5)
    }

    // MARK: - Codable round-trip stress

    @Test func codable_roundTrip_1000items() throws {
        let items = (0..<1000).map { i in
            ClipboardItem(id: UUID(), type: .text, text: "codable item \(i)", contentHash: "hash\(i)", createdAt: Date())
        }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(items)
        let decoded = try decoder.decode([ClipboardItem].self, from: data)

        #expect(decoded.count == 1000)
    }
}

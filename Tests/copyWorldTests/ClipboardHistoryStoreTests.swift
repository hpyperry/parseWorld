import Foundation
import Testing
@testable import copyWorld

@MainActor
@Suite(.serialized)
struct ClipboardHistoryStoreTests {

    private static var itemsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("copyWorld/items", isDirectory: true)
    }

    static func cleanItems() throws {
        let url = itemsURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Save

    @Test func save_addsItem() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let item = ClipboardItem(text: "first")

        store.save(item: item)
        #expect(store.items.count == 1)
        #expect(store.items[0].text == "first")
        try Self.cleanItems()
    }

    @Test func save_newestItemFirst() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        store.save(item: ClipboardItem(text: "first"))
        store.save(item: ClipboardItem(text: "second"))

        #expect(store.items.count == 2)
        #expect(store.items[0].text == "second")
        #expect(store.items[1].text == "first")
        try Self.cleanItems()
    }

    @Test func save_deduplicatesByContentHash() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let item1 = ClipboardItem(text: "hello")
        let item2 = ClipboardItem(text: "hello")

        store.save(item: item1)
        store.save(item: item2)

        #expect(store.items.count == 1)
        #expect(store.items[0].id == item2.id)
        try Self.cleanItems()
    }

    @Test func save_differentTypesDifferentHashes_notDeduped() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let textItem = ClipboardItem(text: "hello")
        let rtfData = "{\\rtf1 hello}".data(using: .utf8)!
        let rtfItem = ClipboardItem(rtfData: rtfData, plainText: "hello")

        store.save(item: textItem)
        store.save(item: rtfItem, rtfData: rtfData)

        #expect(store.items.count == 2)
        try Self.cleanItems()
    }

    // MARK: - Max items

    @Test func save_respectsMaxItems() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 5, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 5)

        for i in 0..<10 {
            store.save(item: ClipboardItem(text: "item \(i)"))
        }

        #expect(store.items.count == 5)
        #expect(store.items[0].text == "item 9")
        try Self.cleanItems()
    }

    @Test func togglePinned_movesItemToTopAndPersists() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let old = ClipboardItem(text: "old", createdAt: Date(timeIntervalSince1970: 0))
        let new = ClipboardItem(text: "new", createdAt: Date(timeIntervalSince1970: 1))

        store.save(item: old)
        store.save(item: new)
        store.togglePinned(itemID: old.id)

        #expect(store.items[0].id == old.id)
        #expect(store.items[0].isPinned)
        #expect(storage.loadAllMetadata()[0].id == old.id)
        try Self.cleanItems()
    }

    @Test func save_duplicateKeepsPinnedState() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let original = ClipboardItem(text: "same")

        store.save(item: original)
        store.togglePinned(itemID: original.id)
        store.save(item: ClipboardItem(text: "same"))

        #expect(store.items.count == 1)
        #expect(store.items[0].isPinned)
        try Self.cleanItems()
    }

    // MARK: - Remove

    @Test func remove_deletesItem() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        let item = ClipboardItem(text: "test")
        store.save(item: item)

        store.remove(itemID: item.id)
        #expect(store.items.isEmpty)
        try Self.cleanItems()
    }

    @Test func remove_nonexistentItem_noCrash() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        store.save(item: ClipboardItem(text: "test"))

        store.remove(itemID: UUID())
        #expect(store.items.count == 1)
        try Self.cleanItems()
    }

    // MARK: - Clear

    @Test func clear_removesAll() throws {
        try Self.cleanItems()
        let storage = ClipboardStorage(maxItems: 30, inMemory: true)
        let store = ClipboardHistoryStore(storage: storage, maximumItems: 30)
        for i in 0..<5 {
            store.save(item: ClipboardItem(text: "item \(i)"))
        }

        store.clear()
        #expect(store.items.isEmpty)
        try Self.cleanItems()
    }

    // MARK: - Persistence

    @Test func items_persistAcrossInstances() throws {
        try Self.cleanItems()
        let storage1 = ClipboardStorage(maxItems: 30, inMemory: true)
        let store1 = ClipboardHistoryStore(storage: storage1, maximumItems: 30)
        store1.save(item: ClipboardItem(text: "persisted"))

        let storage2 = ClipboardStorage(maxItems: 30, modelContainer: storage1.modelContainer)
        let store2 = ClipboardHistoryStore(storage: storage2, maximumItems: 30)

        #expect(store2.items.count == 1)
        #expect(store2.items[0].text == "persisted")
        try Self.cleanItems()
    }
}

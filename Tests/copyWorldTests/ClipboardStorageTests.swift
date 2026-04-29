import AppKit
import Foundation
import Testing
@testable import copyWorld

/// Storage tests use the real items directory but clean up before/after.
@MainActor
@Suite(.serialized)
struct ClipboardStorageTests {

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

    // MARK: - Save and load text

    @Test func saveAndLoad_textItem() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)
        let item = ClipboardItem(text: "hello world")

        try storage.save(item: item, rtfData: nil, imageData: nil)
        let loaded = storage.loadAllMetadata()

        #expect(loaded.count == 1)
        #expect(loaded[0].text == "hello world")
        #expect(loaded[0].type == .text)
        try Self.cleanItemsDirectory()
    }

    @Test func loadAllMetadata_emptyInitially() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)
        #expect(storage.loadAllMetadata().isEmpty)
    }

    // MARK: - Save and load RTF

    @Test func saveAndLoad_RTFItem() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)
        let rtfData = "{\\rtf1\\ansi Bold \\b test \\b0}".data(using: .utf8)!
        let item = ClipboardItem(rtfData: rtfData, plainText: "Bold test")

        try storage.save(item: item, rtfData: rtfData, imageData: nil)

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 1)
        #expect(loaded[0].type == .rtf)

        let loadedRTF = try storage.loadRTFData(for: item.id)
        #expect(loadedRTF == rtfData)
        try Self.cleanItemsDirectory()
    }

    // MARK: - Save and load image

    @Test func saveAndLoad_imageItem() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)
        let image = NSImage(size: NSSize(width: 50, height: 50), flipped: false) { $0.fill(); return true }
        let tiffData = image.tiffRepresentation!
        let item = ClipboardItem(imageData: tiffData, format: "tiff")

        try storage.save(item: item, rtfData: nil, imageData: tiffData)

        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 1)
        #expect(loaded[0].type == .image)

        let loadedImage = try storage.loadImageData(for: item.id, format: "tiff")
        #expect(loadedImage == tiffData)
        try Self.cleanItemsDirectory()
    }

    @Test func saveImage_thumbnailPersisted() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)
        let image = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { $0.fill(); return true }
        let tiffData = image.tiffRepresentation!
        let item = ClipboardItem(imageData: tiffData, format: "tiff")

        try storage.save(item: item, rtfData: nil, imageData: tiffData)

        let thumbnail = storage.loadThumbnail(for: item.id)
        #expect(thumbnail != nil)
        try Self.cleanItemsDirectory()
    }

    // MARK: - Delete

    @Test func delete_removesItem() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)
        let item = ClipboardItem(text: "test")
        try storage.save(item: item, rtfData: nil, imageData: nil)
        #expect(storage.loadAllMetadata().count == 1)

        try storage.delete(itemID: item.id)
        #expect(storage.loadAllMetadata().count == 0)
        try Self.cleanItemsDirectory()
    }

    // MARK: - Clear

    @Test func clear_removesAllItems() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 10)
        for i in 0..<5 {
            let item = ClipboardItem(text: "item \(i)")
            try storage.save(item: item, rtfData: nil, imageData: nil)
        }
        #expect(storage.loadAllMetadata().count == 5)

        try storage.clearAll()
        #expect(storage.loadAllMetadata().count == 0)
        try Self.cleanItemsDirectory()
    }

    // MARK: - Prune

    @Test func save_prunesOldItems() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 3)
        for i in 0..<10 {
            let item = ClipboardItem(text: "item \(i)")
            try storage.save(item: item, rtfData: nil, imageData: nil)
        }
        let loaded = storage.loadAllMetadata()
        #expect(loaded.count == 3)
        #expect(loaded[0].text == "item 9") // newest first
        try Self.cleanItemsDirectory()
    }

    // MARK: - Load image

    @Test func loadImage_returnsNSImage() throws {
        try Self.cleanItemsDirectory()
        let storage = ClipboardStorage(maxItems: 5)
        let image = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { $0.fill(); return true }
        let tiffData = image.tiffRepresentation!
        let item = ClipboardItem(imageData: tiffData, format: "tiff")

        try storage.save(item: item, rtfData: nil, imageData: tiffData)

        let loaded = storage.loadImage(for: item.id, format: "tiff")
        #expect(loaded != nil)
        try Self.cleanItemsDirectory()
    }
}

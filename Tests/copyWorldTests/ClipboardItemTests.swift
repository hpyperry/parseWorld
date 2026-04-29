import AppKit
import Foundation
import Testing
@testable import copyWorld

@MainActor
struct ClipboardItemTests {

    // MARK: - Text initialization

    @Test func textInit_setsCorrectType() {
        let item = ClipboardItem(text: "hello")
        #expect(item.type == .text)
        #expect(item.text == "hello")
    }

    @Test func textInit_computesContentHash() {
        let item = ClipboardItem(text: "hello")
        #expect(!item.contentHash.isEmpty)
        #expect(item.contentHash == ClipboardItem.sha256("hello"))
    }

    @Test func textInit_differentTextsHaveDifferentHashes() {
        let a = ClipboardItem(text: "hello")
        let b = ClipboardItem(text: "world")
        #expect(a.contentHash != b.contentHash)
    }

    @Test func textInit_sameTextsHaveSameHash() {
        let a = ClipboardItem(text: "hello")
        let b = ClipboardItem(text: "hello")
        #expect(a.contentHash == b.contentHash)
    }

    // MARK: - RTF initialization

    @Test func rtfInit_setsCorrectType() throws {
        let rtf = "{\\rtf1 Hello}".data(using: .utf8)!
        let item = ClipboardItem(rtfData: rtf, plainText: "Hello")
        #expect(item.type == .rtf)
        #expect(item.text == "Hello")
        #expect(item.rtfData == rtf)
    }

    @Test func rtfInit_hashIsBasedOnRTFData() throws {
        let rtf1 = "{\\rtf1 Hello}".data(using: .utf8)!
        let rtf2 = "{\\rtf1 World}".data(using: .utf8)!
        let a = ClipboardItem(rtfData: rtf1, plainText: "x")
        let b = ClipboardItem(rtfData: rtf2, plainText: "x")
        #expect(a.contentHash != b.contentHash)
    }

    // MARK: - Image initialization

    @Test func imageInit_setsCorrectType() throws {
        let image = NSImage(size: NSSize(width: 100, height: 80), flipped: false) { $0.fill(); return true }
        let tiff = image.tiffRepresentation!
        let item = ClipboardItem(imageData: tiff, format: "tiff")
        #expect(item.type == .image)
        #expect(item.imageFormat == "tiff")
    }

    @Test func imageInit_generatesThumbnail() throws {
        let image = NSImage(size: NSSize(width: 200, height: 100), flipped: false) { $0.fill(); return true }
        let tiff = image.tiffRepresentation!
        let item = ClipboardItem(imageData: tiff, format: "tiff")
        #expect(item.thumbnail != nil)
        #expect(item.thumbnail!.size.width <= 48)
        #expect(item.thumbnail!.size.height <= 48)
    }

    @Test func imageInit_titleIncludesDimensions() throws {
        let image = NSImage(size: NSSize(width: 1920, height: 1080), flipped: false) { $0.fill(); return true }
        let tiff = image.tiffRepresentation!
        let item = ClipboardItem(imageData: tiff, format: "png")
        #expect(item.title.contains("1920"))
        #expect(item.title.contains("1080"))
    }

    @Test func imageInit_corruptDataFallback() {
        let corrupt = Data([0xFF, 0xFE, 0x00, 0x01])
        let item = ClipboardItem(imageData: corrupt, format: "png")
        #expect(item.type == .image)
        #expect(item.title == String(localized: "(Image)"))
        #expect(item.image == nil)
    }

    // MARK: - Title truncation

    @Test func title_truncatesLongText() {
        let long = String(repeating: "a", count: 200)
        let item = ClipboardItem(text: long)
        #expect(item.title.count <= 81) // 80 + ellipsis
        #expect(item.title.hasSuffix("\u{2026}"))
    }

    @Test func title_emptyText() {
        let item = ClipboardItem(text: "   ")
        #expect(item.title == String(localized: "(Empty Text)"))
    }

    // MARK: - Subtitle

    @Test func subtitle_truncatesTo220() {
        let long = String(repeating: "b", count: 300)
        let item = ClipboardItem(text: long)
        #expect(item.subtitle.count <= 220)
    }

    // MARK: - Equatable

    @Test func equatable_sameID() {
        let id = UUID()
        let a = ClipboardItem(id: id, text: "hello")
        let b = ClipboardItem(id: id, text: "world")
        #expect(a == b)
    }

    @Test func equatable_differentID() {
        let a = ClipboardItem(text: "hello")
        let b = ClipboardItem(text: "hello")
        #expect(a != b)
    }

    // MARK: - Codable round-trip

    @Test func codable_roundTrip_preservesPersistedFields() throws {
        let item = ClipboardItem(text: "test")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(item)
        let decoded = try decoder.decode(ClipboardItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.type == item.type)
        #expect(decoded.text == item.text)
        #expect(decoded.contentHash == item.contentHash)
        #expect(decoded.createdAt.timeIntervalSince1970.isEqual(to: item.createdAt.timeIntervalSince1970))
    }

    @Test func codable_excludesTransientFields() throws {
        let rtf = "{\\rtf1 test}".data(using: .utf8)!
        let item = ClipboardItem(rtfData: rtf, plainText: "test")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        #expect(decoded.rtfData == nil)
        #expect(decoded.image == nil)
        #expect(decoded.thumbnail == nil)
    }

    // MARK: - SHA256

    @Test func sha256_knownVector() {
        let hash = ClipboardItem.sha256("abc")
        #expect(hash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func sha256_emptyString() {
        let hash = ClipboardItem.sha256("")
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func sha256_data() {
        let data = "hello".data(using: .utf8)!
        let hash = ClipboardItem.sha256(data)
        #expect(!hash.isEmpty)
        #expect(hash.count == 64) // SHA256 hex is 64 chars
    }
}

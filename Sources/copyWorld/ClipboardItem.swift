import AppKit
import CryptoKit
import Foundation

struct ClipboardItem: Codable, Identifiable, Equatable {
    private static let titleCharacterLimit = 80

    // MARK: - Persisted fields

    let id: UUID
    let type: ClipboardContentType
    var text: String
    let contentHash: String
    var createdAt: Date
    var imageFormat: String?

    // MARK: - Transient fields (loaded on demand from disk)

    var rtfData: Data?
    var image: NSImage?
    var thumbnail: NSImage?

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, text, contentHash, createdAt, imageFormat
    }

    // MARK: - Initializers

    init(id: UUID = UUID(), type: ClipboardContentType, text: String, contentHash: String, createdAt: Date = .now, imageFormat: String? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.imageFormat = imageFormat
    }

    init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.type = .text
        self.text = text
        self.contentHash = Self.sha256(text)
        self.createdAt = createdAt
        self.imageFormat = nil
    }

    init(id: UUID = UUID(), rtfData: Data, plainText: String, createdAt: Date = .now) {
        self.id = id
        self.type = .rtf
        self.text = plainText
        self.contentHash = Self.sha256(rtfData)
        self.createdAt = createdAt
        self.imageFormat = nil
        self.rtfData = rtfData
    }

    init(id: UUID = UUID(), imageData: Data, format: String, createdAt: Date = .now) {
        self.id = id
        self.type = .image
        self.imageFormat = format
        self.contentHash = Self.sha256(imageData)
        self.createdAt = createdAt

        if let img = NSImage(data: imageData) {
            self.image = img
            self.thumbnail = Self.generateThumbnail(from: img)
            self.text = Self.imageTitle(from: img, format: format)
        } else {
            self.text = "(Image)"
        }
    }

    // MARK: - Computed properties

    var title: String {
        switch type {
        case .text, .rtf:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "(Empty Text)" }
            if trimmed.count > Self.titleCharacterLimit {
                let prefixLength = max(Self.titleCharacterLimit - 1, 0)
                return String(trimmed.prefix(prefixLength)) + "\u{2026}"
            }
            return trimmed
        case .image:
            return text
        }
    }

    var subtitle: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(220))
    }

    // MARK: - Helpers

    static func sha256(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        return sha256(data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    static func generateThumbnail(from image: NSImage, maxSize: CGFloat = 48) -> NSImage? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height)
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        return NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    static func imageTitle(from image: NSImage, format: String) -> String {
        let size = image.size
        let w = Int(size.width)
        let h = Int(size.height)
        let fmt = format.uppercased()
        return "(Image \u{2014} \(fmt), \(w)\u{00d7}\(h))"
    }
}

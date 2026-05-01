import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.copyworld.clipboard", category: "storage")

/// Old ClipboardItem format used before multi-type support (UserDefaults JSON).
private struct LegacyClipboardItem: Codable {
    let id: UUID
    let text: String
    let createdAt: Date
}

@MainActor
final class ClipboardStorage {
    let itemsDirectory: URL
    private let fileManager: FileManager
    private let maxItems: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let migrationKey = "clipboard.storage.migrated"
    private static let legacyDataKey = "clipboard.history.items"

    init(maxItems: Int = 30, fileManager: FileManager = .default) {
        self.maxItems = maxItems
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        itemsDirectory = appSupport.appendingPathComponent("copyWorld/items", isDirectory: true)

        ensureDirectoryExists()
        migrateIfNeeded()
    }

    // MARK: - Load

    func loadAllMetadata() -> [ClipboardItem] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil)
        } catch {
            logger.error("Failed to read items directory: \(error.localizedDescription)")
            return []
        }

        let itemDirs = contents.filter { $0.hasDirectoryPath }
        var items: [ClipboardItem] = []

        for dir in itemDirs {
            let metadataURL = dir.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  var item = try? decoder.decode(ClipboardItem.self, from: data) else {
                logger.error("Failed to load metadata for \(dir.lastPathComponent)")
                continue
            }

            let thumbnailURL = dir.appendingPathComponent("thumbnail.png")
            if let thumbnailData = try? Data(contentsOf: thumbnailURL) {
                item.thumbnail = NSImage(data: thumbnailData)
            }

            items.append(item)
        }

        items.sort { $0.createdAt > $1.createdAt }
        return items
    }

    // MARK: - Save

    func save(item: ClipboardItem, rtfData: Data?, imageData: Data?) throws {
        let itemDir = itemsDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)

        // Write metadata.json (atomic: write to tmp then rename)
        let metadataURL = itemDir.appendingPathComponent("metadata.json")
        let metadataTmp = itemDir.appendingPathComponent("metadata.tmp")
        let metadataJSON = try encoder.encode(item)
        try metadataJSON.write(to: metadataTmp)
        _ = try fileManager.replaceItemAt(metadataURL, withItemAt: metadataTmp)

        // Write content files
        if let rtfData {
            let rtfURL = itemDir.appendingPathComponent("content.rtf")
            try rtfData.write(to: rtfURL)
        }

        if let imageData {
            let ext = item.imageFormat == "png" ? "content.png" : "content.tiff"
            let imgURL = itemDir.appendingPathComponent(ext)
            try imageData.write(to: imgURL)
        }

        // Write thumbnail
        if let thumbnail = item.thumbnail, let tiffData = thumbnail.tiffRepresentation {
            let thumbnailURL = itemDir.appendingPathComponent("thumbnail.png")
            if let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try pngData.write(to: thumbnailURL)
            }
        }

        try prune()
    }

    // MARK: - Load content on demand

    func loadRTFData(for itemID: UUID) throws -> Data {
        let rtfURL = itemsDirectory
            .appendingPathComponent(itemID.uuidString, isDirectory: true)
            .appendingPathComponent("content.rtf")
        return try Data(contentsOf: rtfURL)
    }

    func loadImageData(for itemID: UUID, format: String) throws -> Data {
        let ext = format == "png" ? "content.png" : "content.tiff"
        let imgURL = itemsDirectory
            .appendingPathComponent(itemID.uuidString, isDirectory: true)
            .appendingPathComponent(ext)
        return try Data(contentsOf: imgURL)
    }

    func loadImage(for itemID: UUID, format: String) -> NSImage? {
        guard let data = try? loadImageData(for: itemID, format: format) else { return nil }
        return NSImage(data: data)
    }

    func loadThumbnail(for itemID: UUID) -> NSImage? {
        let thumbnailURL = itemsDirectory
            .appendingPathComponent(itemID.uuidString, isDirectory: true)
            .appendingPathComponent("thumbnail.png")
        guard let data = try? Data(contentsOf: thumbnailURL) else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Delete & Clear

    func delete(itemID: UUID) throws {
        let itemDir = itemsDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: itemDir.path) {
            try fileManager.removeItem(at: itemDir)
        }
    }

    func clearAll() throws {
        guard fileManager.fileExists(atPath: itemsDirectory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil)
        for url in contents where url.hasDirectoryPath {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Prune

    func prune() throws {
        var items = loadAllMetadata()
        guard items.count > maxItems else { return }

        items.sort { $0.createdAt > $1.createdAt }
        let toDelete = items.suffix(items.count - maxItems)

        for item in toDelete {
            do {
                try delete(itemID: item.id)
            } catch {
                logger.error("Failed to prune item \(item.id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: itemsDirectory.path) else { return }
        do {
            try fileManager.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create items directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        let defaults = UserDefaults.standard

        guard !defaults.bool(forKey: Self.migrationKey) else { return }

        guard let legacyData = defaults.data(forKey: Self.legacyDataKey) else {
            defaults.set(true, forKey: Self.migrationKey)
            return
        }

        let legacyItems: [LegacyClipboardItem]
        do {
            legacyItems = try decoder.decode([LegacyClipboardItem].self, from: legacyData)
        } catch {
            logger.error("Failed to decode legacy clipboard data: \(error.localizedDescription)")
            defaults.set(true, forKey: Self.migrationKey)
            return
        }

        guard !legacyItems.isEmpty else {
            defaults.set(true, forKey: Self.migrationKey)
            return
        }

        logger.info("Migrating \(legacyItems.count) items from UserDefaults to file-system storage")

        for legacy in legacyItems {
            let item = ClipboardItem(id: legacy.id, text: legacy.text, createdAt: legacy.createdAt)
            do {
                try save(item: item, rtfData: nil, imageData: nil)
            } catch {
                logger.error("Failed to migrate item \(legacy.id): \(error.localizedDescription)")
            }
        }

        defaults.set(true, forKey: Self.migrationKey)
        logger.info("Migration complete")
    }
}

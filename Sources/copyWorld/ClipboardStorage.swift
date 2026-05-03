import AppKit
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.copyworld.clipboard", category: "storage")

/// Old ClipboardItem format used before multi-type support (UserDefaults JSON).
private struct LegacyClipboardItem: Codable {
    let id: UUID
    let text: String
    let createdAt: Date
}

@Model
final class ClipboardRecord {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var text: String
    var contentHash: String
    var createdAt: Date
    var imageFormat: String?
    var isPinned: Bool = false

    @Attribute(.externalStorage) var rtfData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?

    init(
        id: UUID,
        typeRawValue: String,
        text: String,
        contentHash: String,
        createdAt: Date,
        imageFormat: String?,
        isPinned: Bool = false,
        rtfData: Data?,
        imageData: Data?,
        thumbnailData: Data?
    ) {
        self.id = id
        self.typeRawValue = typeRawValue
        self.text = text
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.imageFormat = imageFormat
        self.isPinned = isPinned
        self.rtfData = rtfData
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }
}

@MainActor
final class ClipboardStorage {
    let itemsDirectory: URL

    private let fileManager: FileManager
    private let maxItems: Int
    let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let shouldRunMigrations: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let swiftDataUserDefaultsMigrationKey = "clipboard.swiftdata.migrated.userdefaults"
    private static let swiftDataFileMigrationKey = "clipboard.swiftdata.migrated.file-storage"
    private static let legacyDataKey = "clipboard.history.items"

    init(
        maxItems: Int = 100,
        fileManager: FileManager = .default,
        modelContainer: ModelContainer? = nil,
        inMemory: Bool = false
    ) {
        self.maxItems = maxItems
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("copyWorld", isDirectory: true)
        itemsDirectory = appDirectory.appendingPathComponent("items", isDirectory: true)

        self.shouldRunMigrations = modelContainer == nil && !inMemory

        if let modelContainer {
            self.modelContainer = modelContainer
        } else {
            self.modelContainer = Self.makeModelContainer(
                appDirectory: appDirectory,
                fileManager: fileManager,
                inMemory: inMemory
            )
        }
        self.modelContext = ModelContext(self.modelContainer)

        if shouldRunMigrations {
            migrateIfNeeded()
        }
        try? prune()
    }

    // MARK: - Load

    func loadAllMetadata() -> [ClipboardItem] {
        do {
            return try fetchRecordsSorted().map(item(from:))
        } catch {
            logger.error("Failed to fetch clipboard records: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Save

    func save(item: ClipboardItem, rtfData: Data?, imageData: Data?) throws {
        for record in try fetchRecords().filter({ $0.id == item.id || $0.contentHash == item.contentHash }) {
            modelContext.delete(record)
        }

        let thumbnailData = Self.pngData(from: item.thumbnail)
        let record = ClipboardRecord(
            id: item.id,
            typeRawValue: item.type.rawValue,
            text: item.text,
            contentHash: item.contentHash,
            createdAt: item.createdAt,
            imageFormat: item.imageFormat,
            isPinned: item.isPinned,
            rtfData: rtfData ?? item.rtfData,
            imageData: imageData,
            thumbnailData: thumbnailData
        )
        modelContext.insert(record)
        try modelContext.save()
        try prune()
    }

    // MARK: - Load content on demand

    func loadRTFData(for itemID: UUID) throws -> Data {
        guard let data = try record(for: itemID)?.rtfData else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }

    func loadImageData(for itemID: UUID, format: String) throws -> Data {
        guard let data = try record(for: itemID)?.imageData else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }

    func loadImage(for itemID: UUID, format: String) -> NSImage? {
        guard let data = try? loadImageData(for: itemID, format: format) else { return nil }
        return NSImage(data: data)
    }

    func loadThumbnail(for itemID: UUID) -> NSImage? {
        guard let data = try? record(for: itemID)?.thumbnailData else { return nil }
        return NSImage(data: data)
    }

    func setPinned(itemID: UUID, isPinned: Bool) throws {
        guard let record = try record(for: itemID) else { return }
        record.isPinned = isPinned
        try modelContext.save()
    }

    // MARK: - Delete & Clear

    func delete(itemID: UUID) throws {
        guard let record = try record(for: itemID) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    func clearAll() throws {
        for record in try fetchRecords() {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    // MARK: - Prune

    func prune() throws {
        let items = try fetchRecordsSorted()
        let unpinnedItems = items.filter { !$0.isPinned }
        guard unpinnedItems.count > maxItems else { return }

        for record in unpinnedItems.suffix(unpinnedItems.count - maxItems) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    // MARK: - Private

    private static func makeModelContainer(
        appDirectory: URL,
        fileManager: FileManager,
        inMemory: Bool
    ) -> ModelContainer {
        let schema = Schema([ClipboardRecord.self])
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            do {
                try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create app support directory: \(error.localizedDescription)")
            }
            let storeURL = appDirectory.appendingPathComponent("Clipboard.sqlite")
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    private func fetchRecords() throws -> [ClipboardRecord] {
        try modelContext.fetch(FetchDescriptor<ClipboardRecord>())
    }

    private func fetchRecordsSorted() throws -> [ClipboardRecord] {
        try fetchRecords().sorted(by: Self.sortRecords)
    }

    private func record(for itemID: UUID) throws -> ClipboardRecord? {
        try fetchRecords().first { $0.id == itemID }
    }

    private func item(from record: ClipboardRecord) -> ClipboardItem {
        let type = ClipboardContentType(rawValue: record.typeRawValue) ?? .text
        var item = ClipboardItem(
            id: record.id,
            type: type,
            text: record.text,
            contentHash: record.contentHash,
            createdAt: record.createdAt,
            imageFormat: record.imageFormat,
            isPinned: record.isPinned
        )
        if let thumbnailData = record.thumbnailData {
            item.thumbnail = NSImage(data: thumbnailData)
        }
        return item
    }

    private static func pngData(from image: NSImage?) -> Data? {
        guard let image, let tiffData = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:])
    }

    private static func sortRecords(_ lhs: ClipboardRecord, _ rhs: ClipboardRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        return lhs.createdAt > rhs.createdAt
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        migrateFileStorageIfNeeded()
        migrateUserDefaultsIfNeeded()
    }

    private func migrateFileStorageIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.swiftDataFileMigrationKey) else { return }

        guard fileManager.fileExists(atPath: itemsDirectory.path) else {
            defaults.set(true, forKey: Self.swiftDataFileMigrationKey)
            return
        }

        let existingRecords = (try? fetchRecords()) ?? []
        guard existingRecords.isEmpty else {
            defaults.set(true, forKey: Self.swiftDataFileMigrationKey)
            return
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil)
        } catch {
            logger.error("Failed to read legacy items directory: \(error.localizedDescription)")
            defaults.set(true, forKey: Self.swiftDataFileMigrationKey)
            return
        }

        let itemDirs = contents.filter { $0.hasDirectoryPath }
        guard !itemDirs.isEmpty else {
            defaults.set(true, forKey: Self.swiftDataFileMigrationKey)
            return
        }

        logger.info("Migrating \(itemDirs.count) items from file-system storage to SwiftData")

        for dir in itemDirs {
            let metadataURL = dir.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let item = try? decoder.decode(ClipboardItem.self, from: data) else {
                logger.error("Failed to load legacy metadata for \(dir.lastPathComponent)")
                continue
            }

            let rtfData = try? Data(contentsOf: dir.appendingPathComponent("content.rtf"))
            let imageData = legacyImageData(for: item, in: dir)
            let thumbnailData = try? Data(contentsOf: dir.appendingPathComponent("thumbnail.png"))

            let record = ClipboardRecord(
                id: item.id,
                typeRawValue: item.type.rawValue,
                text: item.text,
                contentHash: item.contentHash,
                createdAt: item.createdAt,
                imageFormat: item.imageFormat,
                isPinned: item.isPinned,
                rtfData: rtfData,
                imageData: imageData,
                thumbnailData: thumbnailData
            )
            modelContext.insert(record)
        }

        do {
            try modelContext.save()
            try prune()
            defaults.set(true, forKey: Self.swiftDataFileMigrationKey)
            logger.info("File-system migration complete")
        } catch {
            logger.error("Failed to finish file-system migration: \(error.localizedDescription)")
        }
    }

    private func migrateUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.swiftDataUserDefaultsMigrationKey) else { return }

        guard let legacyData = defaults.data(forKey: Self.legacyDataKey) else {
            defaults.set(true, forKey: Self.swiftDataUserDefaultsMigrationKey)
            return
        }

        let legacyItems: [LegacyClipboardItem]
        do {
            legacyItems = try decoder.decode([LegacyClipboardItem].self, from: legacyData)
        } catch {
            logger.error("Failed to decode legacy clipboard data: \(error.localizedDescription)")
            defaults.set(true, forKey: Self.swiftDataUserDefaultsMigrationKey)
            return
        }

        guard !legacyItems.isEmpty else {
            defaults.set(true, forKey: Self.swiftDataUserDefaultsMigrationKey)
            return
        }

        logger.info("Migrating \(legacyItems.count) items from UserDefaults to SwiftData")

        for legacy in legacyItems {
            let item = ClipboardItem(id: legacy.id, text: legacy.text, createdAt: legacy.createdAt)
            do {
                try save(item: item, rtfData: nil, imageData: nil)
            } catch {
                logger.error("Failed to migrate item \(legacy.id): \(error.localizedDescription)")
            }
        }

        defaults.set(true, forKey: Self.swiftDataUserDefaultsMigrationKey)
        logger.info("UserDefaults migration complete")
    }

    private func legacyImageData(for item: ClipboardItem, in dir: URL) -> Data? {
        switch item.imageFormat {
        case "png":
            return try? Data(contentsOf: dir.appendingPathComponent("content.png"))
        case "tiff":
            return try? Data(contentsOf: dir.appendingPathComponent("content.tiff"))
        default:
            return (try? Data(contentsOf: dir.appendingPathComponent("content.png")))
                ?? (try? Data(contentsOf: dir.appendingPathComponent("content.tiff")))
        }
    }
}

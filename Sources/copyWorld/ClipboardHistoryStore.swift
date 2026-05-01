import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.copyworld.clipboard", category: "history-store")

@MainActor
@Observable
final class ClipboardHistoryStore {
    private(set) var items: [ClipboardItem] = []

    private let storage: ClipboardStorage
    private let maximumItems: Int

    init(storage: ClipboardStorage, maximumItems: Int = 30) {
        self.storage = storage
        self.maximumItems = maximumItems
        load()
    }

    func save(item: ClipboardItem, rtfData: Data? = nil, imageData: Data? = nil) {
        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            items.remove(at: existingIndex)
        }

        items.insert(item, at: 0)
        items = Array(items.prefix(maximumItems))
        persist(item: item, rtfData: rtfData, imageData: imageData)
    }

    func remove(itemID: UUID) {
        items.removeAll { $0.id == itemID }
        do {
            try storage.delete(itemID: itemID)
        } catch {
            logger.error("Failed to delete item \(itemID): \(error.localizedDescription)")
        }
    }

    func clear() {
        items.removeAll()
        do {
            try storage.clearAll()
        } catch {
            logger.error("Failed to clear storage: \(error.localizedDescription)")
        }
    }

    private func load() {
        items = storage.loadAllMetadata()
    }

    private func persist(item: ClipboardItem, rtfData: Data?, imageData: Data?) {
        do {
            try storage.save(item: item, rtfData: rtfData, imageData: imageData)
        } catch {
            assertionFailure("Failed to persist clipboard history: \(error)")
        }
    }
}

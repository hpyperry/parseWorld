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

    init(storage: ClipboardStorage, maximumItems: Int = 100) {
        self.storage = storage
        self.maximumItems = maximumItems
        load()
    }

    func save(item: ClipboardItem, rtfData: Data? = nil, imageData: Data? = nil) {
        var itemToSave = item
        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            itemToSave.isPinned = items[existingIndex].isPinned
            items.remove(at: existingIndex)
        }

        items.insert(itemToSave, at: 0)
        sortAndTrimItems()
        persist(item: itemToSave, rtfData: rtfData, imageData: imageData)
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

    func togglePinned(itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }

        items[index].isPinned.toggle()
        let isPinned = items[index].isPinned
        sortAndTrimItems()

        do {
            try storage.setPinned(itemID: itemID, isPinned: isPinned)
            try storage.prune()
        } catch {
            logger.error("Failed to update pinned state for item \(itemID): \(error.localizedDescription)")
        }
    }

    private func load() {
        items = storage.loadAllMetadata()
    }

    private func sortAndTrimItems() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }

        let pinnedItems = items.filter(\.isPinned)
        let unpinnedItems = items.filter { !$0.isPinned }
        items = pinnedItems + Array(unpinnedItems.prefix(maximumItems))
    }

    private func persist(item: ClipboardItem, rtfData: Data?, imageData: Data?) {
        do {
            try storage.save(item: item, rtfData: rtfData, imageData: imageData)
        } catch {
            assertionFailure("Failed to persist clipboard history: \(error)")
        }
    }
}

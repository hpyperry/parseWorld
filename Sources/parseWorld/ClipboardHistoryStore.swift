import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let defaultsKey = "clipboard.history.items"
    private let maximumItems: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults

    init(maximumItems: Int = 30, userDefaults: UserDefaults = .standard) {
        self.maximumItems = maximumItems
        self.userDefaults = userDefaults
        load()
    }

    func save(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let existingIndex = items.firstIndex(where: { $0.text == text }) {
            items.remove(at: existingIndex)
        }

        items.insert(ClipboardItem(text: text), at: 0)
        items = Array(items.prefix(maximumItems))
        persist()
    }

    func remove(itemID: UUID) {
        items.removeAll { $0.id == itemID }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func load() {
        guard let data = userDefaults.data(forKey: defaultsKey) else {
            return
        }

        do {
            items = try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(items)
            userDefaults.set(data, forKey: defaultsKey)
        } catch {
            assertionFailure("Failed to persist clipboard history: \(error)")
        }
    }
}

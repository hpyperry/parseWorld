import Foundation

struct ClipboardItem: Codable, Identifiable, Equatable {
    private static let titleCharacterLimit = 80

    let id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    var title: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "(Empty Text)"
        }

        if trimmed.count > Self.titleCharacterLimit {
            let prefixLength = max(Self.titleCharacterLimit - 1, 0)
            return String(trimmed.prefix(prefixLength)) + "…"
        }

        return trimmed
    }

    var subtitle: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        return String(trimmed.prefix(220))
    }
}

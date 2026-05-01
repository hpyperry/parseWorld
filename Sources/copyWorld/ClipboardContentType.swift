import Foundation

enum ClipboardContentType: String, Codable, CaseIterable, Sendable {
    case text
    case rtf
    case image
}

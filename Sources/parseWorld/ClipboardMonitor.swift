import AppKit
import Foundation

protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    @discardableResult
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: ClipboardPasteboard {}

@MainActor
final class ClipboardMonitor: ObservableObject {
    private let pasteboard: ClipboardPasteboard
    private let historyStore: ClipboardHistoryStore
    private var pollingTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var ignoredContent: String?
    private var isCaptureSuspended = false

    init(pasteboard: ClipboardPasteboard = NSPasteboard.general, historyStore: ClipboardHistoryStore) {
        self.pasteboard = pasteboard
        self.historyStore = historyStore
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [self] in
            while !Task.isCancelled {
                checkForChanges()

                do {
                    try await Task.sleep(for: .milliseconds(800))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func copy(_ item: ClipboardItem) {
        ignoredContent = item.text
        _ = pasteboard.clearContents()
        _ = pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func setCaptureSuspended(_ isSuspended: Bool) {
        isCaptureSuspended = isSuspended
    }

    func processPendingChange() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        if isCaptureSuspended {
            ignoredContent = nil
            return
        }

        guard let text = pasteboard.string(forType: .string) else {
            return
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if ignoredContent == text {
            ignoredContent = nil
            return
        }

        ignoredContent = nil
        historyStore.save(text: text)
    }

    private func checkForChanges() {
        processPendingChange()
    }
}

import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.copyworld.clipboard", category: "monitor")

@MainActor
protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
    @discardableResult
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: ClipboardPasteboard {}

@MainActor
final class ClipboardMonitor {
    private let pasteboard: ClipboardPasteboard
    private let historyStore: ClipboardHistoryStore
    private let storage: ClipboardStorage
    private var pollingTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var ignoredContentHash: String?
    private var isCaptureSuspended = false

    init(
        pasteboard: ClipboardPasteboard = NSPasteboard.general,
        historyStore: ClipboardHistoryStore,
        storage: ClipboardStorage
    ) {
        self.pasteboard = pasteboard
        self.historyStore = historyStore
        self.storage = storage
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard pollingTask == nil else { return }

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
        switch item.type {
        case .text:
            ignoredContentHash = item.contentHash
            _ = pasteboard.clearContents()
            _ = pasteboard.setString(item.text, forType: .string)

        case .rtf:
            let loadedData: Data?
            if item.rtfData != nil {
                loadedData = item.rtfData
            } else {
                do {
                    loadedData = try storage.loadRTFData(for: item.id)
                } catch {
                    logger.error("Failed to load RTF data for item \(item.id): \(error.localizedDescription)")
                    loadedData = nil
                }
            }
            let rtfData = loadedData
            ignoredContentHash = rtfData.map { ClipboardItem.sha256($0) } ?? item.contentHash
            _ = pasteboard.clearContents()
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.text, forType: .string)
            if let rtfData {
                pbItem.setData(rtfData, forType: .rtf)
            }
            _ = pasteboard.writeObjects([pbItem])

        case .image:
            let imageToWrite = item.image ?? storage.loadImage(for: item.id, format: item.imageFormat ?? "png")
            ignoredContentHash = imageToWrite?.tiffRepresentation.map { ClipboardItem.sha256($0) } ?? item.contentHash
            _ = pasteboard.clearContents()
            if let tiffData = imageToWrite?.tiffRepresentation {
                let pbItem = NSPasteboardItem()
                pbItem.setData(tiffData, forType: .tiff)
                _ = pasteboard.writeObjects([pbItem])
            }
        }

        lastChangeCount = pasteboard.changeCount
    }

    func setCaptureSuspended(_ isSuspended: Bool) {
        isCaptureSuspended = isSuspended
    }

    func processPendingChange() {
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        if isCaptureSuspended {
            ignoredContentHash = nil
            return
        }

        // Priority: image > RTF > text
        if let pngData = pasteboard.data(forType: .png) {
            captureImage(pngData, format: "png")
        } else if let tiffData = pasteboard.data(forType: .tiff) {
            captureImage(tiffData, format: "tiff")
        } else if let rtfData = pasteboard.data(forType: .rtf) {
            let plainText = pasteboard.string(forType: .string) ?? ""
            let hash = ClipboardItem.sha256(rtfData)
            guard hash != ignoredContentHash else {
                ignoredContentHash = nil
                return
            }
            ignoredContentHash = nil
            guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let item = ClipboardItem(rtfData: rtfData, plainText: plainText)
            historyStore.save(item: item, rtfData: rtfData, imageData: nil)
        } else if let text = pasteboard.string(forType: .string) {
            let hash = ClipboardItem.sha256(text)
            guard hash != ignoredContentHash else {
                ignoredContentHash = nil
                return
            }
            ignoredContentHash = nil
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            historyStore.save(item: ClipboardItem(text: text))
        }
    }

    private func checkForChanges() {
        processPendingChange()
    }

    private func captureImage(_ data: Data, format: String) {
        let hash = ClipboardItem.sha256(data)
        guard hash != ignoredContentHash else {
            ignoredContentHash = nil
            return
        }
        ignoredContentHash = nil

        let item = ClipboardItem(imageData: data, format: format)
        historyStore.save(item: item, rtfData: nil, imageData: data)
    }
}

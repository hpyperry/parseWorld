import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var historyStore: ClipboardHistoryStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let monitor: ClipboardMonitor
    let storage: ClipboardStorage

    @State private var searchText = ""
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var isPreviewPresented = false
    @State private var listIdentity = UUID()
    @State private var copiedItemID: ClipboardItem.ID?

    private var filteredItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return historyStore.items
        }

        return historyStore.items.filter { item in
            switch item.type {
            case .text, .rtf:
                return item.text.localizedCaseInsensitiveContains(query)
            case .image:
                return false
            }
        }
    }

    private var selectedItem: ClipboardItem? {
        if let selectedItemID,
           let item = filteredItems.first(where: { $0.id == selectedItemID }) {
            return item
        }
        return filteredItems.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clipboard History")
                    .font(.headline)

                Spacer()

                Menu {
                    Button(launchAtLoginManager.isEnabled
                        ? String(localized: "Disable Launch at Login")
                        : String(localized: "Enable Launch at Login")) {
                        launchAtLoginManager.setEnabled(!launchAtLoginManager.isEnabled)
                    }

                    Divider()

                    Button("Clear All", role: .destructive) {
                        historyStore.clear()
                    }
                    .disabled(historyStore.items.isEmpty)

                    Divider()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Search clipboard history", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Items Yet",
                    systemImage: "clipboard",
                    description: Text("Copy text, formatted text, or images anywhere on your Mac and they will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        ClipboardRow(
                            item: item,
                            isSelected: selectedItem?.id == item.id,
                            isCopied: copiedItemID == item.id,
                            onSelect: {
                                selectedItemID = item.id
                                isPreviewPresented = true
                            },
                            onCopy: {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                monitor.copy(item)
                                copiedItemID = item.id
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.5))
                                    if copiedItemID == item.id {
                                        copiedItemID = nil
                                    }
                                }
                            },
                            onDelete: {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

                                let visibleItemsBeforeDelete = filteredItems
                                let deletedIndex = visibleItemsBeforeDelete.firstIndex { $0.id == item.id }
                                let wasPreviewPresented = isPreviewPresented
                                let wasDeletingSelectedItem = (selectedItemID == item.id)

                                historyStore.remove(itemID: item.id)

                                guard wasDeletingSelectedItem else {
                                    return
                                }

                                let remainingItems = visibleItemsBeforeDelete.filter { $0.id != item.id }
                                if remainingItems.isEmpty {
                                    selectedItemID = nil
                                    isPreviewPresented = false
                                    return
                                }

                                if wasPreviewPresented {
                                    if let deletedIndex {
                                        let targetIndex = max(0, deletedIndex - 1)
                                        selectedItemID = remainingItems[targetIndex].id
                                    } else {
                                        selectedItemID = remainingItems.first?.id
                                    }
                                } else {
                                    if let deletedIndex {
                                        let targetIndex = min(deletedIndex, remainingItems.count - 1)
                                        selectedItemID = remainingItems[targetIndex].id
                                    } else {
                                        selectedItemID = remainingItems.first?.id
                                    }
                                }
                            }
                        )
                        .listRowBackground(Color.clear)
                    }
                }
                .id(listIdentity)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minWidth: 420)
                .frame(height: isPreviewPresented ? 240 : 320)

                if isPreviewPresented, let selectedItem {
                    ClipboardPreview(
                        item: selectedItem,
                        storage: storage,
                        onClose: {
                            isPreviewPresented = false
                        }
                    )
                }
            }

            Divider()

            HStack {
                Text("\(historyStore.items.count) saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if launchAtLoginManager.isEnabled {
                    Label("Launch at login on", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let statusMessage = launchAtLoginManager.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 460)
        .animation(.none, value: isPreviewPresented)
        .onChange(of: searchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                listIdentity = UUID()
            }
            syncSelection()
        }
        .onChange(of: historyStore.items.first?.id) { _, _ in
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                listIdentity = UUID()
            }
            syncSelection(preferTopItem: true)
        }
        .onAppear {
            launchAtLoginManager.refresh()
            syncSelection(preferTopItem: true)
        }
    }

    private func syncSelection(preferTopItem: Bool = false) {
        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        if preferTopItem {
            selectedItemID = filteredItems.first?.id
        } else if selectedItemID == nil {
            selectedItemID = filteredItems.first?.id
        }

        if selectedItemID == nil {
            isPreviewPresented = false
        }
    }
}

// MARK: - ClipboardRow

private struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var copyLabel: String {
        item.type == .image ? String(localized: "Copy Image") : String(localized: "Copy")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    typeIcon

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Button(action: onCopy) {
                    if isCopied {
                        Label("Copied", systemImage: "checkmark")
                    } else {
                        Label(copyLabel, systemImage: "doc.on.doc")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isCopied ? .green : .accentColor)
                .disabled(isCopied)

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .animation(.smooth(duration: 0.2), value: isCopied)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.type {
        case .text:
            EmptyView()
        case .rtf:
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
                .font(.title3)
        case .image:
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
    }
}

// MARK: - ClipboardPreview

private struct ClipboardPreview: View {
    let item: ClipboardItem
    let storage: ClipboardStorage
    let onClose: () -> Void

    @State private var rtfData: Data?
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Full Preview")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button("Close Preview", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            previewContent
        }
        .task {
            switch item.type {
            case .rtf where item.rtfData == nil:
                rtfData = try? storage.loadRTFData(for: item.id)
            case .image where item.image == nil:
                image = storage.loadImage(for: item.id, format: item.imageFormat ?? "png")
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.type {
        case .text:
            TextPreview(text: item.text)

        case .rtf:
            let data = item.rtfData ?? rtfData
            if let data {
                RTFPreview(rtfData: data)
            } else {
                TextPreview(text: item.text)
            }

        case .image:
            let img = item.image ?? image
            if let img {
                ImagePreview(image: img)
            } else {
                ContentUnavailableView(
                    "Image Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Could not load image data.")
                )
                .frame(height: 220)
            }
        }
    }
}

// MARK: - TextPreview

private struct TextPreview: View {
    let text: String

    var body: some View {
        SelectablePreviewTextView(text: text, isRichText: false)
            .frame(height: 220)
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - RTFPreview

private struct RTFPreview: View {
    let rtfData: Data

    var body: some View {
        RTFPreviewTextView(rtfData: rtfData)
            .frame(height: 220)
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - ImagePreview

private struct ImagePreview: View {
    let image: NSImage

    var body: some View {
        ImagePreviewView(image: image)
            .frame(height: 220)
            .padding(10)
            .background(CheckerboardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - SelectablePreviewTextView (NSViewRepresentable)

private struct SelectablePreviewTextView: NSViewRepresentable {
    let text: String
    let isRichText: Bool

    final class Coordinator {
        var lastRenderedText: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = isRichText
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        context.coordinator.lastRenderedText = text

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        guard context.coordinator.lastRenderedText != text else { return }

        textView.string = text
        context.coordinator.lastRenderedText = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}

// MARK: - RTFPreviewTextView (NSViewRepresentable)

private struct RTFPreviewTextView: NSViewRepresentable {
    let rtfData: Data

    final class Coordinator {
        var lastRenderedData: Data?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        let attributed = NSAttributedString(
            rtf: rtfData,
            documentAttributes: nil
        ) ?? NSAttributedString(string: String(localized: "(Unable to render RTF)"))

        textView.textStorage?.setAttributedString(attributed)
        context.coordinator.lastRenderedData = rtfData

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        guard context.coordinator.lastRenderedData != rtfData else { return }

        let attributed = NSAttributedString(
            rtf: rtfData,
            documentAttributes: nil
        ) ?? NSAttributedString(string: String(localized: "(Unable to render RTF)"))

        textView.textStorage?.setAttributedString(attributed)
        context.coordinator.lastRenderedData = rtfData
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}

// MARK: - ImagePreviewView (NSViewRepresentable)

private struct ImagePreviewView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSScrollView {
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = imageView
        scrollView.backgroundColor = .clear
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let imageView = nsView.documentView as? NSImageView else { return }
        imageView.image = image
        imageView.frame.size = image.size
    }
}

// MARK: - CheckerboardBackground

private struct CheckerboardBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CheckerboardView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CheckerboardView: NSView {
    private let squareSize: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        let light = NSColor(white: 0.92, alpha: 1)
        let dark = NSColor(white: 0.78, alpha: 1)

        let cols = Int(ceil(bounds.width / squareSize))
        let rows = Int(ceil(bounds.height / squareSize))

        for row in 0..<rows {
            for col in 0..<cols {
                let isDark = (row + col) % 2 == 0
                let color = isDark ? dark : light
                let rect = NSRect(
                    x: CGFloat(col) * squareSize,
                    y: CGFloat(row) * squareSize,
                    width: squareSize,
                    height: squareSize
                )
                color.setFill()
                rect.fill()
            }
        }
    }
}

import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var historyStore: ClipboardHistoryStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let monitor: ClipboardMonitor

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
            item.text.localizedCaseInsensitiveContains(query)
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
                    Button(launchAtLoginManager.isEnabled ? "Disable Launch at Login" : "Enable Launch at Login") {
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

            TextField("Search copied text", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Items Yet",
                    systemImage: "clipboard",
                    description: Text("Copy some text anywhere on your Mac and it will appear here.")
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

private struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
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
                        Label("Copy", systemImage: "doc.on.doc")
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
}

private struct ClipboardPreview: View {
    let item: ClipboardItem
    let onClose: () -> Void

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

            SelectablePreviewTextView(text: item.text)
            .frame(height: 220)
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct SelectablePreviewTextView: NSViewRepresentable {
    let text: String

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
        textView.isRichText = false
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
        guard context.coordinator.lastRenderedText != text else {
            return
        }

        textView.string = text
        context.coordinator.lastRenderedText = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}

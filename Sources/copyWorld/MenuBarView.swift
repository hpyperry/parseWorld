import SwiftUI

struct MenuBarView: View {
    @ObservedObject var historyStore: ClipboardHistoryStore
    let monitor: ClipboardMonitor

    @State private var searchText = ""
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var isPreviewPresented = false
    @State private var listIdentity = UUID()

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
                            onSelect: {
                                selectedItemID = item.id
                                isPreviewPresented = true
                            },
                            onCopy: {
                                selectedItemID = item.id
                                monitor.copy(item)
                            },
                            onDelete: {
                                historyStore.remove(itemID: item.id)
                                if selectedItemID == item.id {
                                    selectedItemID = filteredItems.first(where: { $0.id != item.id })?.id
                                    if selectedItemID == nil {
                                        isPreviewPresented = false
                                    }
                                }
                            }
                        )
                    }
                }
                .id(listIdentity)
                .listStyle(.plain)
                .frame(minWidth: 420, minHeight: isPreviewPresented ? 220 : 320)

                if isPreviewPresented, let selectedItem {
                    ClipboardPreview(
                        item: selectedItem,
                        onClose: {
                            isPreviewPresented = false
                        }
                    )
                        .id(selectedItem.id)
                }
            }

            Divider()

            HStack {
                Text("\(historyStore.items.count) saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 460)
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
            monitor.setCaptureSuspended(true)
            syncSelection(preferTopItem: true)
        }
        .onDisappear {
            monitor.setCaptureSuspended(false)
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
                Button("Copy Back", action: onCopy)
                    .buttonStyle(.borderedProminent)

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
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

            ScrollView {
                Text(item.text)
                    .textSelection(.enabled)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
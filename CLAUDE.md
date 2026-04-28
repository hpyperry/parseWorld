# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Open in Xcode (preferred dev flow)
open copyWorld.xcodeproj

# CLI build (Debug)
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug build

# CLI build (Release) and run
./scripts/build_app.sh
./scripts/run_app.sh

# Build DMG for distribution
./scripts/build_dmg.sh

# Quit running instance
./scripts/quit_app.sh

# Regenerate Xcode project after adding/removing files
ruby scripts/generate_xcodeproj.rb
```

There are no formal tests yet — `Tests/copyWorldTests/` contains a skeleton. The integration test is a standalone script: `swift scripts/test_clipboard_monitor.swift`.

## Architecture

A **menu-bar-only** macOS clipboard history app (no Dock icon, `LSUIElement = true`). Written in Swift + SwiftUI, hosted in an AppKit `NSPopover` inside an `NSStatusItem`. Minimum deployment target: macOS 14.0.

**Entry point**: `CopyWorldApp` (`@main`, SwiftUI `App` lifecycle) — sets `.accessory` activation policy, creates `AppDelegate`, hosts a `Settings` scene for the launch-at-login toggle.

**Singleton coordinator**: `AppState` (`@MainActor`, `ObservableObject`) — owns and wires the three services below.

**Core services** (all `@MainActor`):
- `ClipboardMonitor` — polls `NSPasteboard.general` every 800ms via `Task.sleep`. Tracks `changeCount` to detect new content. Has an "ignored items" set to skip text the app itself copied back. Supports `setCaptureSuspended(true)` while the popover is open so internal copies don't pollute history. When suspension ends, any pending external changes are consumed and discarded.
- `ClipboardHistoryStore` — `@Published` array of `ClipboardItem` (max 30), persisted to `UserDefaults` under `"clipboard.history.items"` as JSON. Deduplicates by text on insert. Exposes `save(text:)`, `remove(itemID:)`, `clear()`. Configurable `maximumItems` and `userDefaults` for testability.
- `LaunchAtLoginManager` — thin wrapper around `SMAppService.mainApp`. Tracks status: enabled, requiresApproval, notFound, notRegistered.

**UI** (`StatusBarController` + `MenuBarView.swift`):
- `StatusBarController` (`NSObject`, `@MainActor`) — creates `NSStatusItem` with SF Symbol "clipboard" icon, manages `NSPopover` (460×560, `.transient` behavior). Left-click toggles popover; right-click shows Quit context menu. On popover open: suspends capture; on close: resumes capture, clears text selection recursively, stops event monitors.
- `MenuBarView` — SwiftUI view with search `TextField`, `List` of `ClipboardRow` items, optional `ClipboardPreview` (220px monospaced `NSTextView` via `NSViewRepresentable`), and footer with count + login item status. Selection is preserved across search filtering.
- `SettingsView` — standalone preferences window with launch-at-login toggle.

**Data model**: `ClipboardItem` — `Codable`, `Identifiable`, `Equatable` struct with `id: UUID`, `text: String`, `createdAt: Date`. `title` is first ~80 chars; `subtitle` is first ~220 chars.

## Key design decisions

- **Capture suspension model**: When the popover opens, external clipboard polling is paused. Any clipboard change that occurred while suspended is consumed (ignored) on resume. This plus the "ignored items" set for copy-back operations prevents the app's own clipboard writes from appearing as new history entries.
- **All main-actor**: No background queues or async networking. Everything runs synchronously on `@MainActor`, which is safe because clipboard access and UserDefaults are lightweight on the main thread.
- **Persistence is synchronous**: `UserDefaults` writes happen immediately in `persist()` (called from `save`, `remove`, `clear`). JSON encoding/decoding errors are silently caught.
- **Xcode project is generated**: `scripts/generate_xcodeproj.rb` scans `Sources/` and `Tests/` directories and builds the `.xcodeproj` from scratch using the `xcodeproj` Ruby gem.
- **No sandbox, no hardened runtime**: Sandbox and code signing enforcement are both disabled in the Xcode build settings — this app relies on `NSPasteboard` polling which requires accessibility permissions, not sandbox entitlements.
- **Haptic + visual feedback on actions**: Copy and delete both trigger `NSHapticFeedbackManager.defaultPerformer.perform(.alignment)`. Copy additionally shows a brief button state change (`doc.on.doc` + "Copy" → `checkmark` + "Copied", green tint, disabled for 1.5s) tracked via a `@State copiedItemID` in `MenuBarView` with a `Task.sleep` reset. Follow this pattern when adding new destructive or clipboard-mutating actions.

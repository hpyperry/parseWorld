# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Open in Xcode (preferred dev flow)
open copyWorld.xcodeproj

# CLI build (Debug)
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug -destination "platform=macOS,arch=arm64" build

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

70 test cases covering data model, storage, history store, clipboard monitor, pinned items, and stress scenarios (Swift Testing framework, `@Suite(.serialized)` where needed). Run via `xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug -destination "platform=macOS,arch=arm64" test`.

## Architecture

A **menu-bar-only** macOS clipboard history app (no Dock icon, `LSUIElement = true`). Written in Swift 6 + SwiftUI, hosted in an AppKit `NSPopover` inside an `NSStatusItem`. Minimum deployment target: macOS 14.0.

**Entry point**: `CopyWorldApp` (`@main`, SwiftUI `App` lifecycle) — sets `.accessory` activation policy, creates `AppDelegate`, hosts a `Settings` scene for the launch-at-login toggle.

**Singleton coordinator**: `AppState` (`@MainActor`) — owns `ClipboardStorage`, `ClipboardHistoryStore`, `ClipboardMonitor`, and `LaunchAtLoginManager`.

**Core services** (all `@MainActor`):
- `ClipboardMonitor` — polls `NSPasteboard.general` every 800ms via `Task.sleep`. Tracks `changeCount` to detect new content. Captures three content types in priority order: image (`.png`/`.tiff`) > RTF > plain text. Uses SHA256 content hash for dedup. Supports `setCaptureSuspended(true)` while the popover is open so internal copies don't pollute history. When suspension ends, any pending external changes are consumed and discarded. Copy-back writes via `NSPasteboardItem` + `writeObjects`.
- `ClipboardHistoryStore` (`@Observable`) — in-memory `items` array of `ClipboardItem` (max 100 unpinned items, with pinned items preserved above the limit). Delegates persistence to `ClipboardStorage`. Deduplicates by `contentHash` (SHA256), preserving pinned state when duplicate content is copied again. Exposes `save(item:rtfData:imageData:)`, `remove(itemID:)`, `clear()`, `togglePinned(itemID:)`.
- `ClipboardStorage` — SwiftData persistence in `~/Library/Application Support/copyWorld/Clipboard.sqlite` using `ClipboardRecord` (`@Model`). RTF/image/thumbnail blobs use external storage attributes. Keeps the existing storage API for callers, loads metadata eagerly, and loads rich/image content on demand. Handles one-time migration from the previous file-system store (`copyWorld/items/<uuid>/metadata.json` + content files) and the older UserDefaults format (`"clipboard.history.items"`). Errors are logged via `Logger` to Console.app.
- `LaunchAtLoginManager` (`@Observable`) — thin wrapper around `SMAppService.mainApp`. Tracks status: enabled, requiresApproval, notFound, notRegistered.

**UI** (`StatusBarController` + `MenuBarView.swift`):
- `StatusBarController` (`NSObject`, `@MainActor`) — creates `NSStatusItem` with SF Symbol "clipboard" icon, manages `NSPopover` (460×560, `.transient` behavior). Left-click toggles popover; right-click shows Quit context menu. On popover open: suspends capture; on close: resumes capture, clears text selection recursively, stops event monitors.
- `MenuBarView` — SwiftUI view with search `TextField`, `List` of type-aware `ClipboardRow` items (text/RTF icon/image thumbnail), optional `ClipboardPreview` that switches between `TextPreview` (monospaced NSTextView), `RTFPreview` (rich NSTextView), and `ImagePreview` (NSImageView with checkerboard background). Images excluded from text search. Footer with count + login item status. Selection preserved across search filtering.
- `SettingsView` — standalone preferences window with launch-at-login toggle.

**Data model**: `ClipboardItem` — `Codable`, `Identifiable`, `Equatable`, `Sendable` struct used by UI and monitor with `id: UUID`, `type: ClipboardContentType` (`.text`/`.rtf`/`.image`, also `Sendable`), `text: String` (plain-text fallback), `contentHash: String` (SHA256 for dedup), `createdAt: Date`, `isPinned: Bool`. Transient fields: `rtfData: Data?`, `image: NSImage?`, `thumbnail: NSImage?` (loaded lazily from SwiftData blob fields). `ClipboardRecord` is the SwiftData persistence model.

**Test infrastructure**: `ClipboardPasteboard` protocol (`@MainActor`) abstracts `NSPasteboard` for testability. `FakePasteboard` (in `ClipboardMonitorTests.swift`) implements it with `simulateExternalCopy(text:/rtfData:plainText:/imageData:format:)` helpers. Stress tests in `StressTests.swift` cover storage prune, large content (1MB text, 4K images), SHA256 performance (10MB), dedup, rapid add/remove, and 1000-item Codable round-trips.

## Key design decisions

- **Swift 6 + @Observable**: Uses Swift 6 language mode with strict concurrency checking (`SWIFT_STRICT_CONCURRENCY = complete`). Data flow uses `@Observable` macro (macOS 14+) instead of `ObservableObject`/`@Published`/`@ObservedObject`. Views receive `@Observable` objects directly; `@Bindable` is used when `Binding<T>` is needed.
- **Capture suspension model**: When the popover opens, external clipboard polling is paused. Any clipboard change that occurred while suspended is consumed (ignored) on resume. This plus SHA256 hash-based dedup prevents the app's own clipboard writes from appearing as new history entries.
- **All main-actor**: No background queues or async networking. Everything runs synchronously on `@MainActor`, which is safe because clipboard access and the small SwiftData operations are lightweight on the main thread.
- **SwiftData persistence**: Replaced file-system storage with SwiftData in `~/Library/Application Support/copyWorld/Clipboard.sqlite`. Metadata fields live on `ClipboardRecord`; RTF/image/thumbnail `Data` use `@Attribute(.externalStorage)` and are read on demand for preview/copy-back. Previous file-system data and older UserDefaults data are auto-migrated on first launch and never deleted (safe downgrade).
- **Xcode project is generated**: `scripts/generate_xcodeproj.rb` scans `Sources/` and `Tests/` directories and builds the `.xcodeproj` from scratch using the `xcodeproj` Ruby gem. It also includes `copyWorld/Resources/` assets (Assets.xcassets, Info.plist, Localizable.xcstrings, PrivacyInfo.xcprivacy).
- **Localization**: Uses String Catalog (`Localizable.xcstrings`) for English (source) and Simplified Chinese (zh-Hans). SwiftUI `Text`/`Button`/`Label`/`Toggle`/`TextField`/`ContentUnavailableView` string literals auto-localize via `LocalizedStringKey`. For AppKit API calls (`NSMenuItem`, `NSImage accessibilityDescription`) and computed String properties, use `String(localized:)`. When adding new user-facing strings, add entries to `Localizable.xcstrings`.
- **Privacy manifest**: `PrivacyInfo.xcprivacy` declares FileTimestamp and UserDefaults required-reason API usage, no data collection. UserDefaults is still used for one-time migration markers. Required for non-Mac App Store distribution via DMG.
- **No sandbox, no hardened runtime**: Sandbox and code signing enforcement are both disabled in the Xcode build settings — this app relies on `NSPasteboard` polling which requires accessibility permissions, not sandbox entitlements.
- **Error handling with OSLog**: Storage and monitor errors are logged via `Logger` (subsystem: `com.copyworld.clipboard`, categories: `storage`, `history-store`, `monitor`) for debugging in Console.app. Programming errors use `assertionFailure` for Debug-time crash. User-visible behavior degrades silently (e.g., failed metadata load skips item, failed thumbnail returns nil).
- **Haptic + visual feedback on actions**: Copy and delete both trigger `NSHapticFeedbackManager.defaultPerformer.perform(.alignment)`. Copy additionally shows a brief button state change (`doc.on.doc` + "Copy" → `checkmark` + "Copied", green tint, disabled for 1.5s) tracked via a `@State copiedItemID` in `MenuBarView` with a `Task.sleep` reset. Follow this pattern when adding new destructive or clipboard-mutating actions.

## Versioning & Release

Version is defined in two places (source of truth: `scripts/generate_xcodeproj.rb`):
- `MARKETING_VERSION` — semver display version (e.g. `0.1.0`)
- `CURRENT_PROJECT_VERSION` — integer build number (e.g. `1`)

Release workflow:

```bash
# 1. Bump version in scripts/generate_xcodeproj.rb (MARKETING_VERSION and/or CURRENT_PROJECT_VERSION)
# 2. Regenerate project
ruby scripts/generate_xcodeproj.rb
# 3. Build DMG
./scripts/build_dmg.sh

# 4. Tag and push
git tag v<MARKETING_VERSION>
git push origin v<MARKETING_VERSION>

# 5. Create GitHub release with DMG asset
gh release create v<MARKETING_VERSION> \
  --title "v<MARKETING_VERSION> — <简短描述>" \
  --notes-file - \
  dist/copyWorld.dmg <<'EOF'
## copyWorld v<MARKETING_VERSION>

<发行说明>
EOF
```

The app is unsigned — users need to right-click → Open on first launch (or `xattr -cr copyWorld.app`). No notarization, no Sparkle update framework. Each release is a standalone DMG download.

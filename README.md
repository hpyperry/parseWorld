# copyWorld

[中文](README_zh.md)

A menu-bar-only macOS clipboard history app supporting plain text, rich text (RTF), and images, with English and Simplified Chinese localization.

## Features

- Monitors clipboard for text, formatted text (RTF), and images (PNG/TIFF)
- Saves up to 100 recent items locally with SwiftData persistence, plus pinned items
- Search clipboard history (text/RTF only; images excluded from search)
- Copy any entry back to the system clipboard with original formatting
- Type-aware previews: monospaced text, rich text rendering, image with checkerboard background
- English and Simplified Chinese localization
- Launch at login support
- Delete single items or clear all history

## Tech Stack

- Swift 6 + SwiftUI + AppKit
- `@Observable` (macOS 14+) data flow
- SwiftData persistence (`~/Library/Application Support/copyWorld/Clipboard.sqlite`)
- Privacy manifest (`PrivacyInfo.xcprivacy`)
- Xcode macOS app target (macOS 14.0+)

## Build & Run

```bash
# Open in Xcode
open copyWorld.xcodeproj

# CLI build (Debug)
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug -destination "platform=macOS,arch=arm64" build

# Run tests (70 test cases including 18 stress tests)
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug -destination "platform=macOS,arch=arm64" test

# Build Release .app → dist/
./scripts/build_app.sh

# Build DMG → dist/
./scripts/build_dmg.sh

# Run packaged app
./scripts/run_app.sh

# Regenerate Xcode project after adding/removing files
ruby scripts/generate_xcodeproj.rb
```

## Notes

- The app is unsigned — right-click → Open on first launch (or `xattr -cr copyWorld.app`)
- No sandbox, no notarization, no Sparkle update framework
- Requires accessibility permissions for clipboard access

## Roadmap

### TODO

- [ ] **Global hotkey** — Add a shortcut (recommended ⌃⌥V) to toggle the clipboard history popover, similar to Windows Win+V. Requires global hotkey monitoring and a settings UI for customization.
- [ ] **Pin button optimization** — Move the pin/unpin action from the current UI button to a right-click context menu, reducing UI clutter.
- [ ] **Accessibility** — Add VoiceOver labels to ClipboardRow, accessibilityLabel for search field, VoiceOver notification on copy success, improve status bar icon accessibilityDescription.
- [ ] **Code signing & notarization** — Requires Apple Developer account. Enable Hardened Runtime + Developer ID signing + Notarization.
- [ ] **Clipboard content encryption** — Currently stored in plaintext. Needs an encryption scheme and key management.

### Done

- Swift 6 modernization with strict concurrency checking
- SwiftData persistence replacing file-system storage
- Privacy manifest (PrivacyInfo.xcprivacy)
- Auto-migration from UserDefaults / file-system storage
- Stress tests (large content, high-frequency operations, Codable performance)

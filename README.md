# copyWorld

A menu-bar-only macOS clipboard history app supporting plain text, rich text (RTF), and images, with English and Simplified Chinese localization.

## Features

- Monitors clipboard for text, formatted text (RTF), and images (PNG/TIFF)
- Saves up to 30 items locally with file-system persistence
- Search clipboard history (text/RTF only; images excluded from search)
- Copy any entry back to the system clipboard with original formatting
- Type-aware previews: monospaced text, rich text rendering, image with checkerboard background
- English and Simplified Chinese localization
- Launch at login support
- Delete single items or clear all history

## Tech Stack

- Swift 6 + SwiftUI + AppKit
- `@Observable` (macOS 14+) data flow
- File-system persistence (`~/Library/Application Support/copyWorld/`)
- Privacy manifest (`PrivacyInfo.xcprivacy`)
- Xcode macOS app target (macOS 14.0+)

## Build & Run

```bash
# Open in Xcode
open copyWorld.xcodeproj

# CLI build (Debug)
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug build

# Run tests (65 test cases including 18 stress tests)
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug test

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

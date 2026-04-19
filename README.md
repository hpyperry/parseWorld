# parseWorld

macOS first-version clipboard history app.

## First-Version Plan

### Goal

Ship a local-only menu bar clipboard tool for macOS that behaves like a lightweight clipboard history feature.

### MVP Scope

- Monitor text changes in the macOS clipboard
- Save the latest 30 text entries locally
- Show history from a menu bar window
- Search previous copied text
- Copy an old entry back into the system clipboard
- Delete one item or clear all history

### Out of Scope for V1

- Images, files, and rich text
- Global shortcuts
- Launch at login
- Cloud sync
- App signing and notarization

### Delivery Steps

1. Set up a native macOS app shell with SwiftUI menu bar UI.
2. Add clipboard polling through `NSPasteboard`.
3. Persist clipboard history with `UserDefaults`.
4. Build history browsing, search, copy-back, delete, and clear actions.
5. Add local build/run scripts so the app can be launched without extra project setup.

## Tech Stack

- `Swift`
- `SwiftUI`
- `AppKit`
- `UserDefaults`
- `swiftc` build script for local development

## Local Run

This machine currently has Swift command line tools but not a complete Xcode app toolchain. Because of that, the project uses direct `swiftc` scripts for now.

Build the app:

```bash
./scripts/build_app.sh
```

Run the app:

```bash
./scripts/run_app.sh
```

The built app bundle is created at `.build/app/parseWorld.app`.

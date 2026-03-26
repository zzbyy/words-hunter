# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Debug build
swift build

# Run debug build
.build/debug/WordsHunter

# Quick dev run
./scripts/run.sh

# Release build → dist/Words Hunter.app
./scripts/build.sh

# Run tests
swift test
```

## Architecture

Words Hunter is a macOS menu bar app (.accessory policy, no Dock icon) that captures vocabulary words via `Option + double-click` anywhere on the system, then creates markdown files in an Obsidian vault.

**Word capture flow:**
`EventMonitor` → `TextCapture` → `WordPageCreator` → _(optional)_ `DictionaryService` → `WordPageUpdater` → `BubbleWindow`

**Key design constraints:**
- Zero external dependencies — pure AppKit/Foundation/Security/CoreGraphics
- CGEventTap is listen-only (never consumes events)
- All pasteboard operations and UI must run on main thread
- Dictionary lookup runs as a cancellable `async` Task; never blocks UI

## Source layout

```
Sources/
  WordsHunter/main.swift          # NSApplication bootstrap only
  WordsHunterLib/
    App/AppDelegate.swift         # Lifecycle + orchestration
    Core/
      EventMonitor.swift          # CGEventTap: Option+double-click detection
      TextCapture.swift           # Cmd+C simulation → pasteboard → word extraction
      WordPageCreator.swift       # Markdown template writer
      DictionaryService.swift     # Merriam-Webster API, retry with backoff
      WordPageUpdater.swift       # Atomic update of Definition section
    Models/
      AppSettings.swift           # UserDefaults + Keychain wrapper (singleton)
      KeychainHelper.swift        # Keychain CRUD for MW API key
    UI/
      StatusBarController.swift   # Menu bar icon + menu
      SetupWindow.swift           # First-run config + Preferences (same window)
      BubbleWindow.swift          # Floating pill animation with sound/haptic
```

## Important patterns

**AppSettings migration guard:** `useWordFolder` defaults to `true` for existing installs (preserves subfolder behavior) and `false` for new installs. The computed property `wordsFolderURL` is the authoritative write location.

**DictionaryService:** 4xx errors (401/403/429) are permanent — no retry. 5xx errors retry with exponential backoff (1, 2, 4, 8, 16s). Word-not-found silently returns nil, leaving the template blank. On success, `WordPageUpdater` aborts if the user has already written content (no clobbering).

**WordPageUpdater safety:** Before writing, checks: (1) file still exists, (2) Definition section body is whitespace-only. Both are abort conditions. Uses atomic temp-file swap via `FileManager.replaceItem()`.

**Testing:** `DictionaryService` and `AppSettings` accept injected dependencies (`URLSessionProtocol`, `UserDefaults`) for test isolation. Tests live in `Tests/WordsHunterTests/WordsHunterTests.swift`.

**SetupWindow** doubles as both first-run setup and the Preferences window — same view controller, button label changes to "Save Settings" when reopened.

# Words Hunter — Product Requirements Document

> **Version**: 1.0
> **Date**: 2026-03-25
> **Platform**: macOS 13+ (Ventura and later)
> **Tech Stack**: Swift 5.9+, AppKit, CoreGraphics (CGEventTap), Swift Package Manager; TypeScript (OpenClaw plugin), Vitest

---

## 1. Product Overview

**Words Hunter** is a macOS native menu bar app for English learners. It lets users capture new vocabulary words from **any app** — Chrome, Books, iTerm2, Ghostty, or any other macOS application — with a single gesture: **Option(⌥) + double-click**.

When a word is captured, the app automatically creates a new markdown page in the user's **Obsidian vault** with a structured template for the user to fill in later (definitions, examples, collocations, synonyms).

### Core Value Proposition

Eliminates the context-switching cost of manually creating vocabulary pages. The user stays in their reading/coding flow and captures words in under a second.

### What This Is NOT

- Not an Obsidian plugin — it's a standalone system-level app
- Not cross-platform — macOS only

> **Note (v1.5+/v1.8+):** Words Hunter auto-fills definitions from the Oxford Learner's Dictionary by default (no API key required). Merriam-Webster is available as an optional fallback. See Settings → Dictionary Lookup.
> **Note (v1.7+):** An OpenClaw TypeScript plugin (`openclaw-plugin/`) adds AI-assisted vocabulary mastery sessions, SRS scheduling, and sighting tracking. See `SCHEMA.md` and `openclaw-plugin/SKILL.md`.

---

## 2. User Flow

```
User reads in Chrome / Books / Terminal
        │
        ▼
Sees an interesting word
        │
        ▼
Holds Option(⌥) and double-clicks the word
        │
        ▼
Word gets selected (normal OS behavior)
  + Words Hunter detects the gesture
        │
        ▼
App captures the selected text via pasteboard
        │
        ▼
Creates {Word}.md in Obsidian vault
        │
        ▼
Shows a cute bubble animation + plays a sound
        │
        ▼
User continues reading — zero disruption
```

---

## 3. Functional Requirements

### 3.1 First-Run Setup

On first launch (when no configuration exists):

1. Show a setup window titled **"Welcome to Words Hunter 🎯"**
2. Two configuration fields:
   - **Vault Path**: Absolute path to the Obsidian vault folder. Must include a "Browse" button that opens a native macOS folder picker (`NSOpenPanel`).
   - **Word Folder**: Subfolder name within the vault where word pages will be created. Default value: `"Words"`. This is just the folder name, not a full path.
3. A **"Start Hunting"** button that:
   - Validates the vault path exists
   - Creates the word folder inside the vault if it doesn't exist
   - Saves settings
   - Closes the setup window
   - Activates the event monitor

### 3.2 Word Capture — Trigger

| Property | Specification |
|---|---|
| **Gesture** | Option(⌥) + double-click |
| **Scope** | System-wide (works in any macOS app) |
| **Detection method** | `CGEventTap` in listen-only mode |
| **Event to detect** | `leftMouseUp` where `clickState == 2` AND `flags.contains(.maskAlternate)` |
| **Behavior** | Must NOT interfere with the normal double-click word selection. The event tap is listen-only — it observes but does not consume the event. |

### 3.3 Word Capture — Text Extraction

After detecting Option+double-click:

1. **Wait ~150ms** for the word selection to settle in the target app
2. **Save** the current contents of `NSPasteboard.general` (all types)
3. **Simulate `Cmd+C`** by posting `CGEvent` keyboard events (keyDown + keyUp for key code `0x08` with `.maskCommand` flag)
4. **Wait ~150ms** for pasteboard to update
5. **Read** the new string from `NSPasteboard.general`
6. **Restore** the original pasteboard contents
7. **Validate** the captured text:
   - Trim whitespace and newlines
   - Reject if empty
   - Reject if contains spaces (multi-word selection)
   - Reject if not primarily alphabetic characters
8. Return the cleaned word

### 3.4 Page Creation

Given a valid captured word:

1. **Capitalize** the first letter for the filename (e.g., `encapsulate` → `Encapsulate.md`)
2. Construct the file path: `{vaultPath}/{wordFolder}/{Word}.md`
3. **Check if file exists** → if yes, **skip silently** (no feedback, no error)
4. **Create** the word folder if it doesn't exist
5. **Write** the markdown file using the template (see §4)

### 3.5 Visual Feedback — Bubble

When a word is successfully captured (file was created, not skipped):

1. Create a **borderless, transparent `NSPanel`** positioned near the mouse cursor
2. Display the captured word in a **rounded bubble** (pill/speech-bubble shape)
3. **Animation sequence**:
   - Scale from 0 → 1 with spring easing (~0.3s)
   - Hold for ~1.2s
   - Fade out (~0.3s)
   - Remove the window
4. The bubble must be:
   - **Non-interactive** — ignores all mouse events (`ignoresMouseEvents = true`)
   - **Non-activating** — does NOT steal focus from the current app (`NSPanel` with `.nonactivatingPanel` style)
   - **Always on top** — visible above all other windows (`.floating` level)

### 3.6 Sound Feedback

When a word is successfully captured:

- Play the macOS system sound `"Pop"` (fallback: `"Tink"`) via `NSSound`
- Play concurrently with the bubble animation (don't wait for sound to finish)

### 3.7 Menu Bar

The app lives in the macOS menu bar with **no Dock icon** (`LSUIElement = true`).

**Menu bar icon**: Text-based `"🎯"` or SF Symbol `character.book.closed`

**Dropdown menu**:
```
┌─────────────────────────┐
│  Words Hunter            │  (title, disabled)
├─────────────────────────┤
│  Open Vault Folder       │  → Opens word folder in Finder
│  Preferences...          │  → Shows setup window for reconfiguration
├─────────────────────────┤
│  Quit Words Hunter       │  → NSApp.terminate
└─────────────────────────┘
```

### 3.8 Permissions

The app requires **Accessibility** permission to function (for CGEventTap and simulated keystrokes).

On launch:
1. Check if Accessibility is granted via `AXIsProcessTrusted()`
2. If not granted, call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` to show the system prompt
3. Display a helper message in the setup window explaining what to do
4. The event monitor should only start after Accessibility is confirmed

---

## 4. Word Page Template

Each captured word creates a markdown file. The filename is the word with the first letter capitalized (e.g., `Posit.md`, `Encapsulate.md`).

**Template content** (as of v1.6 — Obsidian-native format):

```markdown
> [!info] {Word}
> //

## Sightings
- {YYYY-MM-DD} — *(context sentence where you saw the word)*

---

## Meanings

### 1. () *()*

> *()*

**My sentence:**
-

**Patterns:**
- *(common word combinations and grammar patterns)*

---

## When to Use

**Where it fits:**
**In casual speech:**

---

## Word Family

*(list related forms, each with a short example)*

---

## See Also
*(link to other captured words with a note on how they differ)*

---

## Memory Tip
*(optional: etymology, mnemonic, personal association — anything that helps you remember)*
```

Where:
- `{Word}` = captured word with first letter capitalized (also used as the filename, e.g. `Posit.md`)
- `{YYYY-MM-DD}` = date of capture (local timezone)
- The `> [!info]` callout renders as an Obsidian info block with the word as the title

The sections are intentionally left partially empty for the user to fill in during study sessions. The OpenClaw mastery plugin (v1.7+) appends a `> [!mastery]` callout and `### Best Sentences` section as the user works through sessions.

---

## 5. Technical Architecture

### 5.1 Project Structure

```
Words Hunter/
├── Package.swift                          # SPM manifest (macOS 13+, no dependencies)
├── Sources/
│   ├── WordsHunterLib/                    # Library target (testable)
│   │   ├── Core/
│   │   │   ├── EventMonitor.swift         # CGEventTap for Option+double-click
│   │   │   ├── TextCapture.swift          # Pasteboard-based word capture
│   │   │   ├── WordPageCreator.swift      # Markdown file creation
│   │   │   ├── WordPageUpdater.swift      # Atomic definition injection
│   │   │   ├── OxfordScraper.swift        # Oxford Learner's Dictionary HTML scraping
│   │   │   ├── DictionaryService.swift    # Oxford + MW fallback orchestrator
│   │   │   └── VaultScanner.swift         # Vault file enumeration
│   │   ├── UI/
│   │   │   ├── StatusBarController.swift  # Menu bar icon and menu
│   │   │   ├── SetupWindow.swift          # First-run configuration window
│   │   │   └── BubbleWindow.swift         # Floating bubble animation
│   │   └── Models/
│   │       └── AppSettings.swift          # UserDefaults wrapper + config bridge export
│   └── WordsHunter/
│       └── main.swift                     # Entry point: NSApplication bootstrap + AppDelegate
├── openclaw-plugin/                       # TypeScript OpenClaw vocabulary mastery plugin
│   ├── src/
│   │   ├── index.ts                       # Plugin entry point (tools, crons, hooks)
│   │   ├── vault.ts                       # Vault I/O, mastery.json R/W, validateWord
│   │   ├── types.ts                       # ToolResult<T> discriminated union
│   │   ├── srs/scheduler.ts               # Leitner SRS (5 boxes, 85-point threshold)
│   │   ├── tools/                         # scan_vault, load_word, record_mastery, …
│   │   ├── hooks/sighting-hook.ts         # Outgoing message sighting detection
│   │   └── importer.ts                    # One-time import of untracked word pages
│   ├── tests/                             # Vitest unit tests (69 tests, 11 files)
│   ├── SKILL.md                           # OpenClaw agent conversation flow spec
│   └── package.json
├── SCHEMA.md                              # Schema contract: mastery.json, config.json, callouts
├── CHANGELOG.md                           # Version history
├── TODOS.md                               # Deferred work and sprint backlog
├── scripts/
│   ├── build.sh                           # Build + create .app bundle
│   └── run.sh                             # Quick development run
└── PRD.md
```

### 5.2 Component Responsibilities

#### `main.swift`
- Create `NSApplication.shared`
- Set activation policy to `.accessory` (no dock icon)
- Assign `AppDelegate`
- Call `NSApp.run()`

#### `AppDelegate.swift`
- On `applicationDidFinishLaunching`:
  1. Check Accessibility permission via `AXIsProcessTrusted()`
  2. If not trusted, prompt via `AXIsProcessTrustedWithOptions`
  3. Initialize `StatusBarController`
  4. If `AppSettings.isSetupComplete` is false → show `SetupWindow`
  5. If setup is complete → start `EventMonitor`
- Hold strong references to all controllers

#### `AppSettings.swift`
- Singleton accessing `UserDefaults.standard`
- Properties:
  - `vaultPath: String` — absolute path to Obsidian vault
  - `wordFolder: String` — subfolder name (default: `"Words"`)
  - `isSetupComplete: Bool` — first-run flag

#### `EventMonitor.swift`
- Creates `CGEventTap` at `cGSessionEventTap` level, `.listenOnly` mode
- Event mask: `leftMouseUp`
- Callback checks:
  - `mouseEventClickState == 2` (double-click)
  - `flags.contains(.maskAlternate)` (Option key held)
- On match: dispatches to main thread, calls `TextCapture` → `WordPageCreator` → `BubbleWindow`
- Handles tap being disabled by the system (re-enables via `CGEvent.tapEnable`)

#### `TextCapture.swift`
- Static method: `captureSelectedText(completion: @escaping (String?) -> Void)`
- Saves pasteboard → simulates Cmd+C → reads → restores → validates → returns word
- All pasteboard operations on main thread
- Uses `CGEvent` for key simulation with `CGEventSource(stateID: .combinedSessionState)`

#### `WordPageCreator.swift`
- Enum result: `.created(path)`, `.skipped`, `.error(message)`
- Static method: `createPage(for word: String) -> Result`
- Constructs path, checks existence, writes template
- Uses `FileManager` for directory creation and file writing

#### `BubbleWindow.swift`
- Creates `NSPanel` with styles: `.borderless`, `.nonactivatingPanel`
- Properties: `isOpaque = false`, `backgroundColor = .clear`, `ignoresMouseEvents = true`, `level = .floating`
- Content: `NSTextField` styled as a rounded pill with the word text
- Design: dark background (#1a1a2e or similar dark navy), white text, rounded corners (16px), padding, subtle shadow
- Animation: Core Animation — scale transform + opacity
- Positions window at `NSEvent.mouseLocation`, offset slightly upward
- Sound: plays `NSSound(named: "Pop")` on show

#### `SetupWindow.swift`
- `NSWindow` with `NSViewController` containing:
  - Title label: "Welcome to Words Hunter 🎯"
  - Vault Path: `NSTextField` + "Browse" `NSButton` (triggers `NSOpenPanel`)
  - Word Folder: `NSTextField` with placeholder "Words"
  - "Start Hunting" `NSButton`
- Validation: vault path must exist (show alert if not)
- On confirm: saves to `AppSettings`, closes window, notifies delegate to start `EventMonitor`
- Also used for "Preferences..." (same window, pre-filled with current values)

### 5.3 Build & Run

**Development build**:
```bash
cd "/Users/zz/Words Hunter"
swift build
.build/debug/WordsHunter
```

**Release build + app bundle** (via `scripts/build.sh`):
```bash
cd "/Users/zz/Words Hunter"
./scripts/build.sh
```

The build script should:
1. Run `swift build -c release`
2. Create directory structure: `dist/Words Hunter.app/Contents/MacOS/`
3. Copy binary: `cp .build/release/WordsHunter "dist/Words Hunter.app/Contents/MacOS/Words Hunter"`
4. Generate `Info.plist` with:
   - `CFBundleName`: Words Hunter
   - `CFBundleIdentifier`: com.wordshunter.app
   - `LSUIElement`: true (no dock icon)
   - `CFBundleIconFile`: AppIcon (if available)
5. The resulting `.app` can be dragged to `/Applications`

---

## 6. Edge Cases

| Scenario | Behavior |
|---|---|
| Option+double-click but nothing is selected | No text captured → do nothing silently |
| Multi-word selection captured | Reject (contains spaces) → do nothing silently |
| Word page already exists | Skip silently — no bubble, no sound |
| Vault path no longer exists | Show a notification via menu bar that vault is missing |
| Accessibility permission not granted | Show prompt, event monitor stays inactive until granted |
| CGEventTap gets disabled by system | Re-enable it automatically (`CGEvent.tapEnable`) |
| Word contains special characters | Strip non-alphabetic characters, reject if empty after stripping |
| Word has mixed case (e.g., "API") | Preserve original casing for the filename |

---

## 7. Design Aesthetics (Bubble)

The bubble should feel **cute and delightful** — a small reward for capturing a word.

- **Shape**: Rounded pill / capsule (not a tooltip, not a rectangle)
- **Colors**: Dark navy background (`#1a1a2e`), white text, subtle blue shadow
- **Font**: System font, semi-bold, 14pt
- **Size**: Just large enough to fit the word with ~16px horizontal padding, ~8px vertical
- **Position**: Appears ~20px above the mouse cursor
- **Animation**: Spring scale-in gives it a playful "pop" feel
- **Shadow**: Subtle `NSShadow` with 4px blur, dark blue tint

---

## 8. Future Considerations and Shipped Extensions

Features originally deferred from v1, now tracked in `TODOS.md`:

**Shipped:**
- **Auto-dictionary lookup** (v1.5/v1.8) — Oxford Learner's Dictionary scraping (primary, no API key) with MW API fallback, exponential backoff, rate-limit handling
- **OpenClaw mastery plugin** (v1.7) — TypeScript plugin: 6 tools, Leitner SRS, sighting hook, SKILL.md agent flow

**Still deferred (see TODOS.md for details):**
- **AXUIElement sentence capture** — grab the sentence around the word at capture time (P3)
- **Word count stats** — how many words captured this week/month in menu bar
- **Configurable modifier key** — change from Option to Ctrl or other modifiers
- **Launch at login** — auto-start when macOS boots
- **Obsidian URI integration** — open the created page in Obsidian immediately after capture

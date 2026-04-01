# Words Hunter

**Capture any word from any app in under a second. Master it through conversation.**

Words Hunter is a word-capture app for language learners. Hold a modifier key and double-click any word — in Chrome, a PDF reader, a terminal, anywhere — and it instantly creates a structured vocabulary page in your words directory. No context switching. No copy-paste. You stay in your reading flow.

Available on **macOS** (Swift, menu bar app) and **Windows** (Tauri/Rust, system tray app).

Pair it with the OpenClaw mastery plugin and a conversational AI agent coaches you through spaced-repetition practice sessions directly in Telegram, WeChat, or any other chat app you already use.

---

## Platform overview

| | macOS | Windows |
|---|---|---|
| **Trigger** | Option(⌥) + double-click | Alt + double-click |
| **Capture method** | CGEventTap + pasteboard | Win32 keyboard hook + clipboard |
| **Built with** | Swift 5.9, SwiftPM | Rust, Tauri 2, WebView2 |
| **Tray** | Menu bar icon | System tray icon |
| **Requires** | macOS 13 (Ventura)+ | Windows 10/11 |
| **Accessibility** | Accessibility permission | UAC + Settings |

---

## How it works

```
You read something in any app
        │
        ▼
Hold Option(⌥) / Alt and double-click the word
        │
        ▼
Words Hunter captures the word via system event hook + clipboard
        │
        ▼
Creates {word}.md in your words directory with a structured template
        │
        ▼
Plays a sound + shows a bubble near your cursor
        │
        ▼
(Optional) Merriam-Webster definition auto-fills the page
        │
        ▼
Later: /vocab in Telegram → AI agent runs a practice session
        │
        ▼
Word advances through Leitner SRS boxes until mastered
```

---

## Features

- **System-wide capture** — works in Chrome, a PDF reader, a terminal, VS Code, or any app. Never interrupts your workflow.
- **One-gesture trigger** — Option(⌥)+double-click on macOS, Alt+double-click on Windows.
- **Instant feedback** — a small animated bubble appears near your cursor and a soft sound plays. Gone in under 2 seconds.
- **Smart deduplication** — if the word page already exists, capture is silently skipped. No duplicates.
- **Structured template** — each word page includes sections for Sightings, Meanings, When to Use, Word Family, See Also, and Memory Tip. You fill these in at your own pace.
- **Dictionary lookup** — auto-fills definitions from the Merriam-Webster Dictionary API in the background. Requires a free API key; configure it in Settings → Dictionary Lookup.
- **Spaced repetition (SRS)** — Leitner 5-box system via the OpenClaw plugin. Words in box 1 come back in 1 day; box 5 in 30 days.
- **Conversational practice** — an AI agent introduces the word, asks you to use it in a sentence, gives feedback, and scores your best attempt.
- **Mastery tracking** — scores, session history, and the next review date are written back to your word page as a `> [!mastery]` callout.
- **Passive sighting detection** — when you use a captured word in any outgoing message, the sighting is logged silently to the word's page. No pop-ups, no interruptions.
- **24h capture nudges** — a nudge fires 24 hours after capture reminding you to practice the word.
- **Weekly recap** — a Sunday morning summary of your word stats, mastered words, and what's due.

---

## Requirements

### macOS

- **macOS 13 (Ventura) or later**
- **Accessibility permission** — required for CGEventTap (system-wide event monitoring) and simulated Cmd+C
- **Swift 5.9+ / Xcode 15+** — for building from source
- **Merriam-Webster API key** (optional) — free tier at [dictionaryapi.com](https://dictionaryapi.com), 1,000 calls/month
- **OpenClaw** (optional) — for AI mastery sessions. See [openclaw.dev](https://openclaw.dev)

### Windows

- **Windows 10 or 11** (x64)
- **WebView2 runtime** — pre-installed on Windows 11; the installer bundles it for Windows 10
- **Rust toolchain** — for building from source (install from [rustup.rs](https://rustup.rs))
- **Node.js 18+** — for Tauri CLI (build only)
- **Merriam-Webster API key** (optional)
- **OpenClaw** (optional)

---

## Installation

### macOS — build from source

Words Hunter is built with Swift Package Manager. No third-party dependencies.

```bash
git clone https://github.com/zzbyy/words-hunter.git
cd words-hunter
swift build -c release
```

Create the `.app` bundle:

```bash
./scripts/build.sh
```

This produces `dist/Words Hunter.app`. Drag it to `/Applications`.

**Development build:**

```bash
swift build
.build/debug/WordsHunter
```

### Windows — build from source

The Windows version is built with **Tauri 2 (Rust + WebView2)**.

```bash
git clone https://github.com/zzbyy/words-hunter.git
cd words-hunter

# Install Tauri CLI
npm install

# Run in development mode
npm run tauri:dev

# Build the installer (produces WordsHunter_x.x.x_x64-setup.exe)
npm run tauri:build
```

The installer will be at: `src-tauri/target/release/bundle/nsis/WordsHunter_x.x.x_x64-setup.exe`

---

## Setup

### macOS — first launch

1. Open **Words Hunter** from `/Applications` (or run the debug binary).
2. macOS will ask for **Accessibility permission** — grant it in System Settings → Privacy & Security → Accessibility. Words Hunter cannot capture words without it.
3. The setup window appears:
   - **Words Directory** — point this at the folder where you want word pages saved.
   - **Words Folder** — subfolder inside that directory. Default: `Words`. Uncheck the toggle to save directly to the root.
4. Click **Start Hunting**. The menu bar icon appears and capture is active.

### Windows — first launch

1. Run the installer (`WordsHunter_x.x.x_x64-setup.exe`) or the debug binary.
2. Grant **Accessibility permission** when prompted (Windows UAC + Settings).
3. The setup window appears:
   - **Words Directory** — point this at the folder where you want word pages saved.
   - **Words Folder** — subfolder inside that directory. Default: `Words`.
4. Click **Start Hunting**. The system tray icon appears and capture is active.

### Dictionary lookup (optional, both platforms)

1. Get a free API key at [dictionaryapi.com](https://dictionaryapi.com) — select the Collegiate Dictionary entry.
2. Open **Preferences** from the tray icon.
3. Toggle **Enable dictionary lookup** and paste your API key.
4. Capture any word — the definition appears in the `## Meanings` section within a few seconds.

### Customising the word page template (optional)

Click **Edit Word Template…** in Preferences to open `.wordshunter/template.md` in your default editor. Use `{{word}}` and `{{date}}` as placeholders. Changes take effect immediately — no rebuild needed. Delete the file to reset to the default template.

### OpenClaw mastery plugin (optional)

The mastery plugin connects Words Hunter to OpenClaw, an AI agent platform. **Source and install instructions:** [github.com/zzbyy/openclaw-words-hunter](https://github.com/zzbyy/openclaw-words-hunter).

**Prerequisites:** [OpenClaw](https://openclaw.dev) installed and configured with at least one channel connector (Telegram, WeChat, Feishu, WhatsApp, etc.).

**Quick install** (after the package is published to npm as `words-hunter-openclaw`):

```bash
openclaw plugins install words-hunter-openclaw
```

The plugin discovers your words directory via `.wordshunter/config.json`, which Words Hunter writes automatically each time you save settings.

**Start a mastery session:** open any connected chat channel and send `/vocab`.

**Capture a word from chat:** send `/hunt ephemeral` in any connected channel. The word page is created and filled with dictionary data — no desktop app needed.

---

## Usage

### Capturing a word

Hold **Option (⌥)** (macOS) or **Alt** (Windows) and double-click any word in any app. The word gets selected normally and Words Hunter simultaneously:

1. Copies the selection
2. Creates `{word}.md` in your words folder
3. Plays a sound and shows a bubble near your cursor
4. Fetches the definition in the background (if lookup is enabled)

If the word was already captured, nothing happens — silent skip, no duplicate.

### Your word pages

Each captured word creates a file like `posit.md`:

```markdown
# posit

**Syllables:** *(e.g. po·sit)* · **Pronunciation:** *(e.g. /ˈpɒz.ɪt/)*

## Sightings
- 2026-03-29 — *(context sentence where you saw the word)*

---

## Meanings

### 1. () *()*

> *()*

**My sentence:**
- *(write your own sentence using this word)*

**Patterns:**
- *(common word combinations and grammar patterns)*

---

## When to Use

**Where it fits:**
**In casual speech:**

---

## Word Family

...

## See Also
...

## Memory Tip
...
```

Fill in the sections yourself, or let the AI agent help during a mastery session.

### Mastery sessions (OpenClaw)

Send `/vocab` in any connected channel:

```
You have 3 words to practice today: posit, acquire, allude.
Let's start with posit.

posit (verb) — to put forward as fact or as a basis for argument.
Register: formal. Common in academic writing and discourse.
Last practiced: never. Box: 1 (new).

Use posit in a sentence — any context works.
```

The agent runs you through at least 3 exchanges, scores your best sentence on a 4-component rubric (meaning, register, collocation, grammar), and advances the word through the Leitner boxes:

| Box | Interval | Status |
|-----|----------|--------|
| 1 | 1 day | Learning |
| 2 | 3 days | Learning |
| 3 | 7 days | Reviewing |
| 4 | 14 days | Mastered |
| 5 | 30 days | Mastered |

Score ≥ 85 → box advances. Score < 85 → drops one box. Mastery threshold is intentionally high — you need to demonstrate real command, not just recall.

When a word reaches box 4, you graduate it. The agent writes a `## Graduation` section to the page with a memorable sentence:

```markdown
## Graduation
> On 2026-04-15 you mastered this word.
> "The philosopher posited that consciousness arises from complexity itself."
```

### Passive sightings

You don't have to do anything. When you type a captured word in any outgoing message, the sighting hook records it automatically:

```markdown
## Sightings
- 2026-04-01 — "I posit that the test suite is too slow." *(Telegram — work chat)*
- 2026-03-29 — *(context sentence where you saw the word)*
```

Sightings don't affect your SRS score — they're a record of how you're using the word in the wild.

---

## Privacy

Words Hunter operates locally. No data is sent to external servers except:

- **Merriam-Webster API** — the captured word is sent to fetch its definition, if lookup is enabled and a key is configured. No other data is sent.
- **OpenClaw** — practice session messages travel through whatever channels you have connected. The sighting hook reads your *outgoing* messages locally and stores only the matched word + timestamp + sentence in your local `.md` file.

Everything else — your word pages, mastery state, SRS schedule — lives in files on your machine.

---

## Architecture

Words Hunter is two independent systems connected by a single JSON file.

```
┌─────────────────────────────────────┐  ┌─────────────────────────────────────┐
│  macOS App (Swift)                  │  │  Windows App (Rust / Tauri 2)       │
│                                     │  │                                     │
│  CGEventTap → TextCapture           │  │  Win32 hook → TextCapture           │
│      → WordPageCreator (.md file)   │  │      → WordPageCreator (.md file)   │
│      → DictionaryService (MW API)   │  │      → DictionaryService (MW API)   │
│      → WordPageUpdater (definition) │  │      → WordPageUpdater (definition) │
│                                     │  │                                     │
│  AppSettings.exportConfigBridge()   │  │  AppSettings.exportConfigBridge()   │
│      → .wordshunter/config.json     │  │      → .wordshunter/config.json     │
└─────────────────┬───────────────────┘  └──────────────────┬──────────────────┘
                  │                                          │
                  └──────────────────┬───────────────────────┘
                                     │ config.json (words directory)
                                     ▼
              ┌─────────────────────────────────────┐
              │  OpenClaw Plugin (TypeScript)       │
              │                                     │
              │  scan_vault    → mastery.json       │
              │  load_word     → {word}.md          │
              │  record_mastery → mastery.json      │
              │                  + [!mastery] callout│
              │  update_page   → {word}.md          │
              │  record_sighting → {word}.md        │
              │  vault_summary → mastery.json       │
              │                                     │
              │  watcher.ts    → pending-nudges.json│
              │  sighting-hook → record_sighting    │
              └─────────────────────────────────────┘
```

**State stores:**
- `.wordshunter/mastery.json` — canonical SRS state (box, score, next_review, history)
- `{word}.md` — human-readable page; the `> [!mastery]` callout is a derived view rendered from mastery.json
- `.wordshunter/config.json` — written by the native app, read by the TypeScript plugin
- `.wordshunter/template.md` — user-editable word page template (seeded on first save)
- `.wordshunter/pending-nudges.json` — 24h nudge queue

All file writes use atomic rename (write to tmp → rename) on both platforms. See `SCHEMA.md` for the full format contract.

**Test suite:** Vitest unit tests for the OpenClaw plugin run in [openclaw-words-hunter](https://github.com/zzbyy/openclaw-words-hunter). All tests use synthetic fixtures — no personal data in the repo.

---

## Project structure

```
Words Hunter/
├── Sources/                         # macOS app (Swift)
│   ├── WordsHunterLib/
│   │   ├── Core/                    # EventMonitor, TextCapture, WordPageCreator,
│   │   │                            # WordPageUpdater, DictionaryService, VaultScanner
│   │   ├── UI/                      # StatusBarController, SetupWindow, BubbleWindow
│   │   └── Models/                  # AppSettings (UserDefaults + config bridge export)
│   └── WordsHunter/
│       └── main.swift               # App entry point + AppDelegate
├── src-tauri/                       # Windows app (Rust / Tauri 2)
│   ├── src/
│   │   ├── main.rs                  # App entry point
│   │   └── lib.rs                   # Core logic: capture, page creation, dictionary
│   └── Cargo.toml
├── src/                             # Tauri frontend (minimal WebView UI)
├── SCHEMA.md                        # Format contract: mastery.json, config.json, callouts
│                                    # OpenClaw plugin: github.com/zzbyy/openclaw-words-hunter
├── CHANGELOG.md                     # Version history
├── TODOS.md                         # Deferred work and sprint backlog
└── PRD.md                           # Product requirements
```

---

## Contributing

Pull requests welcome. A few things to know:

**macOS app (Swift):**

```bash
swift build          # build
swift test           # run tests
./scripts/build.sh   # create .app bundle in dist/
```

Requires macOS 13+. The `CGEventTap` and Accessibility APIs used for capture are macOS-only.

**Windows app (Rust / Tauri):**

```bash
npm install          # install Tauri CLI
npm run tauri:dev    # development mode
npm run tauri:build  # build installer
cargo test           # run Rust unit tests (from src-tauri/)
```

Requires Windows 10/11. The Win32 keyboard hook APIs are Windows-only.

**OpenClaw plugin (TypeScript):** develop in [openclaw-words-hunter](https://github.com/zzbyy/openclaw-words-hunter) (`npm install`, `npm run build`, `npm test`). Tests use synthetic fixtures. Never commit real word pages or personal data.

**Schema changes:**

If you change the mastery.json schema, callout format, or config.json structure, update `SCHEMA.md` first. The macOS app, Windows app, and TypeScript plugin must all agree on the format — a mismatch will corrupt word pages silently.

**New features:**

Check `TODOS.md` for the backlog. P1 items are unblocking; P2 are quality-of-life; P3 are exploratory. Open an issue before starting anything that touches the schema or the SRS algorithm.

---

## Roadmap

See [TODOS.md](TODOS.md) for the full backlog. High-priority deferred items:

- **mastery.json concurrent write protection** (P1) — guard against lost-update races when two sessions score the same word simultaneously
- **AXUIElement / UIA sentence capture** (P3) — capture the full sentence around the word at capture time, auto-fill the Sightings section
- **Collins Dictionary support** (P2) — second definition source, waiting for an official API
- **Corpus-based collocations** (P3) — pull real word pairs from a corpus API

---

## License

MIT. See [LICENSE](LICENSE) for the full text.

---

## Acknowledgments

Built with:
- [Merriam-Webster Dictionary API](https://dictionaryapi.com) — definitions
- [OpenClaw](https://openclaw.dev) — conversational AI agent platform
- [Tauri](https://tauri.app) — Rust + WebView2 framework for the Windows app
- [chokidar](https://github.com/paulmillr/chokidar) — file watching
- [Vitest](https://vitest.dev) — TypeScript test framework
- [Obsidian](https://obsidian.md) — recommended markdown viewer for word pages

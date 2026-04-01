# Words Hunter

**Capture any word from any app in under a second. Master it through conversation.**

Words Hunter is a macOS menu bar app for language learners. Hold Option and double-click any word — in Chrome, Books, a terminal, anywhere — and it instantly creates a structured vocabulary page in your Obsidian vault. No context switching. No copy-paste. You stay in your reading flow.

Pair it with the OpenClaw mastery plugin and a conversational AI agent coaches you through spaced-repetition practice sessions directly in Telegram, WeChat, or any other chat app you already use.

---

## How it works

```
You read something in any app
        │
        ▼
Hold Option(⌥) and double-click the word
        │
        ▼
Words Hunter captures the word via CGEventTap + pasteboard
        │
        ▼
Creates posit.md in your Obsidian vault with a structured template
        │
        ▼
Plays a "Pop" sound + shows a bubble near your cursor
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

### Capture (v1.0+)

- **System-wide capture** — works in Chrome, Safari, Books, iTerm2, Ghostty, VS Code, or any macOS app. Uses `CGEventTap` in listen-only mode — never interrupts your workflow.
- **One-gesture trigger** — Option(⌥) + double-click. The word gets selected normally; Words Hunter just notices.
- **Instant feedback** — a small animated bubble appears near your cursor and a soft "Pop" plays. Gone in under 2 seconds.
- **Smart deduplication** — if the word page already exists, capture is silently skipped. No duplicates.
- **Structured template** — each word page includes sections for Sightings, Meanings, When to Use, Word Family, See Also, and Memory Tip. You fill these in at your own pace.

### Dictionary lookup (v1.5+)

- **Auto-fills definitions** from the Merriam-Webster Dictionary API when a word is captured.
- Runs in the background and updates the page silently — open Obsidian a few seconds after capture and the definition is already there.
- Requires a free MW API key (1,000 lookups/month). Configure it in Settings → Dictionary Lookup.
- Exponential backoff with configurable retries (1–5). Permanent 4xx errors are not retried.

### AI mastery via OpenClaw (v1.7+)

The `openclaw-plugin/` directory contains a TypeScript plugin for the [OpenClaw](https://openclaw.dev) platform. Install it once and an AI agent coaches you through vocabulary practice in any chat app you already use.

- **Spaced repetition (SRS)** — Leitner 5-box system. Words in box 1 come back in 1 day; box 5 in 30 days. Miss the 85-point threshold and the word drops a box.
- **Conversational practice** — the agent introduces the word, asks you to use it in a sentence, gives feedback, and scores your best attempt.
- **Mastery tracking** — scores, session history, and the next review date are written back to your Obsidian word page as a `> [!mastery]` callout.
- **Passive sighting detection** — when you use a captured word in any outgoing message, the sighting is logged silently to the word's page. No pop-ups, no interruptions.
- **24h capture nudges** — when you capture a word, a nudge fires 24 hours later reminding you to practice it.
- **Weekly recap** — a Sunday morning summary of your vault stats, mastered words, and what's due.

---

## Requirements

- **macOS 13 (Ventura) or later**
- **Accessibility permission** — required for CGEventTap (system-wide event monitoring) and simulated Cmd+C
- **Obsidian** — with at least one vault set up. Words Hunter creates plain `.md` files; Obsidian is optional for reading but it renders the callout blocks and internal links correctly.
- **Swift 5.9+ / Xcode 15+** — for building from source
- **Merriam-Webster API key** (optional) — free tier at [dictionaryapi.com](https://dictionaryapi.com), 1,000 calls/month
- **OpenClaw** (optional) — for AI mastery sessions. See [openclaw.dev](https://openclaw.dev) for setup.

---

## Installation

Words Hunter is built with Swift Package Manager. No third-party dependencies for the macOS app.

### Build from source

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

### Development build

```bash
swift build
.build/debug/WordsHunter
```

---

## Setup

### First launch

1. Open **Words Hunter** from `/Applications` (or run the debug binary).
2. macOS will ask for **Accessibility permission** — grant it in System Settings → Privacy & Security → Accessibility. Words Hunter cannot capture words without it.
3. The setup window appears:
   - **Vault Path** — point this at your Obsidian vault folder (use Browse to pick it).
   - **Words Folder** — subfolder inside the vault where word pages are saved. Default: `Words`. Uncheck the toggle to save directly to the vault root.
4. Click **Start Hunting**. The menu bar icon appears and capture is active.

### Dictionary lookup (optional)

1. Get a free API key at [dictionaryapi.com](https://dictionaryapi.com) — select the Collegiate Dictionary entry.
2. Open **Preferences** from the Words Hunter menu bar icon.
3. Toggle **Enable dictionary lookup** and paste your API key.
4. Capture any word — the definition appears in the `## Meanings` section within a few seconds.

### Customising the word page template (optional)

Click **Edit Word Template…** in Preferences to open `.wordshunter/template.md` in your default editor. Use `{{word}}` and `{{date}}` as placeholders. Changes take effect immediately — no rebuild needed. Delete the file to reset to the default template.

### OpenClaw mastery plugin (optional)

The mastery plugin connects Words Hunter to OpenClaw, an AI agent platform.

**Prerequisites:** [OpenClaw](https://openclaw.dev) installed and configured with at least one channel connector (Telegram, WeChat, Feishu, WhatsApp, etc.).

```bash
cd openclaw-plugin
npm install
npm run build
```

Install the plugin in OpenClaw:

```bash
openclaw plugin install ./openclaw-plugin
```

That's it. The plugin discovers your vault via `.wordshunter/config.json`, which Words Hunter writes automatically each time you save settings.

**Start a mastery session:** open any connected chat channel and send `/vocab`.

**Capture a word from chat:** send `/hunt ephemeral` in any connected channel. The word page is created and auto-filled with Cambridge Dictionary data (definitions, pronunciations, CEFR levels, examples, word family) — no macOS app needed.

---

## Usage

### Capturing a word

Hold **Option (⌥)** and double-click any word in any app. The word gets selected (normal macOS behavior) and Words Hunter simultaneously:

1. Copies the selection
2. Creates `{word}.md` in your words folder
3. Plays a "Pop" sound and shows a bubble near your cursor
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

Everything else — the vault, mastery state, SRS schedule — lives in files on your machine.

---

## Architecture

Words Hunter is two independent systems connected by a single JSON file.

```
┌─────────────────────────────────────┐
│  macOS App (Swift)                  │
│                                     │
│  CGEventTap → TextCapture           │
│      → WordPageCreator (.md file)   │
│      → DictionaryService (MW API)   │
│      → WordPageUpdater (definition) │
│                                     │
│  AppSettings.exportConfigBridge()   │
│      → .wordshunter/config.json     │
└─────────────────┬───────────────────┘
                  │ config.json (vault path + words folder)
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
- `.wordshunter/config.json` — written by Swift app, read by TypeScript plugin
- `.wordshunter/template.md` — user-editable word page template (seeded on first save)
- `.wordshunter/pending-nudges.json` — 24h nudge queue

All file writes in both the Swift app and TypeScript plugin use atomic rename (write to tmp → rename). See `SCHEMA.md` for the full format contract.

**Test suite:** 69 Vitest unit tests across 11 files (TypeScript plugin). All tests use synthetic fixtures — no personal data in the repo.

---

## Project structure

```
Words Hunter/
├── Sources/
│   ├── WordsHunterLib/          # Testable library target
│   │   ├── Core/                # EventMonitor, TextCapture, WordPageCreator,
│   │   │                        # WordPageUpdater, DictionaryService, VaultScanner
│   │   ├── UI/                  # StatusBarController, SetupWindow, BubbleWindow
│   │   └── Models/              # AppSettings (UserDefaults + config bridge export)
│   └── WordsHunter/
│       └── main.swift           # App entry point + AppDelegate
├── openclaw-plugin/             # TypeScript OpenClaw vocabulary mastery plugin
│   ├── src/
│   │   ├── index.ts             # Plugin entry: tools, crons, hooks
│   │   ├── vault.ts             # Vault I/O, mastery.json, validateWord
│   │   ├── types.ts             # ToolResult<T> discriminated union + error codes
│   │   ├── srs/scheduler.ts     # Leitner SRS (5 boxes, 85-point threshold)
│   │   ├── tools/               # scan_vault, load_word, record_mastery,
│   │   │                        # update_page, record_sighting, vault_summary
│   │   ├── hooks/               # sighting-hook.ts
│   │   └── importer.ts          # One-time import of untracked word pages
│   ├── tests/                   # 69 Vitest tests across 11 files
│   └── SKILL.md                 # OpenClaw agent conversation flow spec
├── SCHEMA.md                    # Format contract: mastery.json, config.json, callouts
├── CHANGELOG.md                 # Version history
├── TODOS.md                     # Deferred work and sprint backlog
└── PRD.md                       # Product requirements (v1.0 origin + version notes)
```

---

## Contributing

Pull requests welcome. A few things to know:

**Swift app (macOS):**

```bash
swift build          # build
swift test           # run tests
./scripts/build.sh   # create .app bundle in dist/
```

The app requires macOS 13+. The `CGEventTap` and Accessibility APIs used for capture are macOS-only — there is no cross-platform path.

**OpenClaw plugin (TypeScript):**

```bash
cd openclaw-plugin
npm install
npm run build        # compile to dist/
npm test             # run Vitest suite (69 tests)
```

Tests use synthetic fixtures. Never commit real vault data or personal word pages.

**Schema changes:**

If you change the mastery.json schema, callout format, or config.json structure, update `SCHEMA.md` first. Both the Swift app and TypeScript plugin must agree on the format — a mismatch will corrupt word pages silently.

**New features:**

Check `TODOS.md` for the backlog. P1 items are unblocking; P2 are quality-of-life; P3 are exploratory. Open an issue before starting anything that touches the schema or the SRS algorithm.

---

## Roadmap

See [TODOS.md](TODOS.md) for the full backlog. High-priority deferred items:

- **mastery.json concurrent write protection** (P1) — guard against lost-update races when two sessions score the same word simultaneously
- **AXUIElement sentence capture** (P3) — capture the full sentence around the word at capture time, auto-fill the Sightings section
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
- [chokidar](https://github.com/paulmillr/chokidar) — file watching
- [Vitest](https://vitest.dev) — TypeScript test framework
- [Obsidian](https://obsidian.md) — markdown vault and rendering

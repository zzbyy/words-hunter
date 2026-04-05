# Words Hunter Schema Contract

> Contract between the Swift macOS app (writer) and the TypeScript OpenClaw plugin (reader/writer).
> Both sides must agree on every format defined here. Changes require updating both sides.

---

## 1. Word Page Format (`.md`)

Created by the Swift app (`WordPageCreator.swift`) or the OpenClaw plugin (`create-word.ts`).
Filename: `{lemma.lowercased()}.md`.

Both sides read the user-editable template at `.wordshunter/template.md` (falling back to a
built-in default). Placeholders: `{{word}}` (lemma) and `{{date}}` (YYYY-MM-DD).

**Lookup-time variables** (filled after the Oxford Learner's Dictionary lookup completes):
- `{{pronunciation-bre}}` — British English IPA
- `{{pronunciation-ame}}` — American English IPA
- `{{cefr}}` — CEFR level badge (e.g. "B2")  
- `{{meanings}}` — numbered meaning blocks with CEFR per sense, examples, extra examples
- `{{collocations}}` — collocation groups from the Oxford Collocations Dictionary
- `{{nearby-words}}` — nearby dictionary words with POS
- `{{see-also}}` — `[[wikilink]]` lines for related words found in the vault

### Default Template

```markdown
# {{word}}

**Pronunciation:** 🇬🇧 {{pronunciation-bre}} · 🇺🇸 {{pronunciation-ame}} · **Level:** {{cefr}}

## Meanings
{{meanings}}

## Collocations
{{collocations}}

---

## When to Use

**Where it fits:**
**In casual speech:**

---

## Word Family

*(list related forms, each with a short example)*

---

## Nearby Words
{{nearby-words}}

---

## See Also
{{see-also}}

---

## Memory Tip
*(optional: etymology, mnemonic, personal association — anything that helps you remember)*
```

### Sections added by the OpenClaw plugin

The plugin appends these sections to existing word pages. It never overwrites or
removes sections it did not write.

```markdown
> [!mastery]
> **Status:** learning | reviewing | mastered
> **Box:** 1–5
> **Score:** 0–100
> **Next review:** YYYY-MM-DD
> **Sessions:** N
> **Failures:** ["confused with 'postulate'"]

### Best Sentences
- {YYYY-MM-DD} (score: 85): "I posit that dark matter exists."

### History
- {YYYY-MM-DD}: box 1→2, score 78, sentences: 1

## Graduation
> On {YYYY-MM-DD} you mastered this word. "{LLM-generated sentence using the word}"
```

**Rules:**
- `> [!mastery]` callout is a **derived display view** — regenerated from `mastery.json` by `callout-renderer.ts`. Never manually edited. If corrupted, run `words-hunter repair`.
- `### Best Sentences` — append-only. Never modify or remove existing entries.
- `### History` — append-only. One line per session. Never modify existing entries.
- `## Graduation` — written once. Never overwritten.
- `## Sightings` — removed from new pages. Sightings are now stored in `sightings.json` (see § 6). Old pages may still have this section as historical data.

---

## 2. Mastery Sidecar (`.wordshunter/mastery.json`)

**Canonical SRS state store.** Location: `{vault_root}/.wordshunter/mastery.json`.

The plugin reads and writes this file. The Obsidian callout is derived from it.

### Schema

```json
{
  "version": 1,
  "words": {
    "posit": {
      "word": "posit",
      "box": 3,
      "status": "reviewing",
      "score": 78,
      "last_practiced": "2026-03-29",
      "next_review": "2026-04-05",
      "sessions": 4,
      "failures": ["confused with 'postulate'"],
      "best_sentences": [
        {
          "text": "I posit that dark matter exists.",
          "date": "2026-03-29",
          "score": 85
        }
      ]
    }
  }
}
```

### Field definitions

| Field | Type | Description |
|-------|------|-------------|
| `version` | `number` | Schema version. Currently `1`. |
| `words` | `Record<string, WordEntry>` | Keyed by lowercase word. |
| `word` | `string` | Lowercase word form. |
| `box` | `1–5` | Leitner box. 1=new/struggling, 5=near-mastered. |
| `status` | `"learning" \| "reviewing" \| "mastered"` | Derived: box 1–2=learning, 3=reviewing, 4–5=mastered. |
| `score` | `0–100` | Latest session composite score. |
| `last_practiced` | `YYYY-MM-DD` | Date of last mastery session. |
| `next_review` | `YYYY-MM-DD` | Computed from box interval. |
| `sessions` | `number` | Total number of practice sessions. |
| `failures` | `string[]` | Noted confusion patterns (filled by agent). |
| `best_sentences` | `BestSentence[]` | Top sentences from sessions (append-only). |

### Leitner box intervals

| Box | Interval |
|-----|----------|
| 1 | 1 day |
| 2 | 3 days |
| 3 | 7 days |
| 4 | 14 days |
| 5 | 30 days |

**Scoring rules:**
- Success (score ≥ 85): advance one box (ceiling: 5)
- Failure (score < 85): drop one box (floor: 1)
- Box ≥ 4 → `status = "mastered"`, triggers graduation flow

### Write protocol

All writes to `mastery.json` use **atomic tmp+rename**:
1. Write to `os.tmpdir()/{random}.json`
2. `fs.rename(tmp, mastery.json)` — POSIX atomic on same filesystem
3. Never write partial JSON to the live file

---

## 3. Config Bridge (`.wordshunter/config.json`)

Written by the Swift app (`AppSettings.exportConfigBridge()`) when the user saves settings.
Read by the TypeScript plugin on startup.

### Schema

```json
{
  "vault_path": "/Users/zz/Documents/Obsidian/MyVault",
  "words_folder": "Words"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `vault_path` | `string` | Absolute path to the Obsidian vault root. |
| `words_folder` | `string` | Subfolder name within vault for word pages. Empty string means vault root. |

**Plugin behavior:** If `config.json` is absent or `vault_path` is missing/empty → throw `VAULT_NOT_FOUND`. If `vault_path` does not exist on disk → throw `VAULT_NOT_FOUND`.

---

## 4. Pending Nudges Queue (`.wordshunter/pending-nudges.json`)

Written by `watcher.ts` when a new word page is detected. Read by the 15-minute cron job.

### Schema

```json
{
  "version": 1,
  "nudges": [
    {
      "word": "posit",
      "nudge_due_at": "2026-03-30T09:15:00Z",
      "created_at": "2026-03-29T09:15:00Z"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `word` | `string` | Lowercase word that was captured. |
| `nudge_due_at` | `ISO8601` | When to send the nudge (capture time + 24h). |
| `created_at` | `ISO8601` | When the nudge was enqueued. |

**Write protocol:** Same atomic tmp+rename pattern as `mastery.json`.

**Cron behavior (every 15 minutes):**
1. Read `pending-nudges.json` (return if absent)
2. Find entries where `nudge_due_at ≤ now`
3. For each overdue entry: skip if word already has `mastery.json` entry (user already reviewed), otherwise send nudge to `primary_channel`
4. Remove fired entries, write updated file atomically

---

## 5. Mastery Callout Format

The `> [!mastery]` callout in word `.md` files is the human-readable display layer.
It is generated by `callout-renderer.ts` from `mastery.json`. Never parsed for state — always read state from `mastery.json` directly.

```markdown
> [!mastery]
> **Status:** reviewing
> **Box:** 3  ·  Next review: 2026-04-05
> **Score:** 78  ·  Sessions: 4
> **Failures:** confused with 'postulate'
```

When `failures` is empty, omit the Failures line.

---

## 6. Sightings Store (`sightings.json`)

**Location:** `{vault_root}/.wordshunter/sightings.json`

Centralized, event-based store for all word sightings. Written by the macOS app (Swift),
the Windows app (Rust/Tauri), and the OpenClaw TypeScript plugin. One event per user
action — if a message contains multiple vault words, they share a single event.

The `## Sightings` section in word `.md` pages (§1) is legacy — still present in
templates but no longer the source of truth for sighting data.

### Schema (v2)

```json
{
  "version": 2,
  "days": {
    "2026-04-04": [
      {
        "timestamp": "2026-04-04T21:15",
        "channel": "Telegram",
        "words": {
          "deliberate": "The deliberate attempt to suppress the report.",
          "suppress": "The deliberate attempt to suppress the report."
        }
      },
      {
        "timestamp": "2026-04-04T21:30",
        "words": {
          "posit": ""
        }
      }
    ]
  }
}
```

### Field definitions

| Field | Type | Description |
|-------|------|-------------|
| `version` | `number` | Schema version. Currently `2`. |
| `days` | `Record<string, SightingEvent[]>` | Keyed by YYYY-MM-DD date. |
| `timestamp` | `string` | ISO minute precision: `"YYYY-MM-DDTHH:mm"`. |
| `channel` | `string?` | Source app or channel (e.g. `"Telegram"`, `"Safari"`). Omitted from JSON when absent. |
| `words` | `Record<string, string>` | Lowercase word → context sentence. Empty string if no sentence captured. |

### Write protocol

1. **Read** — parse `sightings.json` (or create empty v2 store if missing)
2. **Migrate** — if `version == 1`, convert to v2 in memory (see below)
3. **Modify** — append new `SightingEvent` to `days[YYYY-MM-DD]`
4. **Prune** — drop days older than 30 from today
5. **Write** — atomic temp+rename with sorted keys and pretty-printed JSON

### v1 → v2 migration

If the store has `version: 1` (word-keyed format), readers convert transparently:

```
v1: days["2026-04-04"]["deliberate"] = [{ date, sentence, channel }]
v2: days["2026-04-04"] = [{ timestamp: "2026-04-04T00:00", channel, words: { deliberate: sentence } }]
```

Entries with the same date and channel are coalesced into a single event. The next write
saves as v2 automatically.

### Auto-prune

Days older than 30 are dropped on every write. This keeps the file small and bounded.

### Cross-platform consistency

- Swift uses `JSONEncoder` with `.sortedKeys` + `.prettyPrinted`
- Rust uses `BTreeMap` (inherently sorted) + `serde_json::to_string_pretty`
- TypeScript plugin uses `proper-lockfile` (mkdir-based) for locking in multi-writer scenarios

---

## Appendix A: OpenClaw Plugin API

> Reference for the TypeScript plugin scaffold (Step 4 of implementation sequence).

### Plugin entry point

```typescript
import { definePluginEntry, registerTool, registerCron, registerHook } from '@openclaw/sdk';

export default definePluginEntry({
  name: 'words-hunter',
  version: '1.0.0',
  onLoad: async (ctx) => {
    // ctx.config — plugin config object
    // ctx.logger — structured logger
    // ctx.channel — send messages to channels
  }
});
```

### Registering a tool

```typescript
registerTool({
  name: 'scan_vault',
  description: 'Scan the Words Hunter vault for due or new words.',
  parameters: {
    type: 'object',
    properties: {
      filter: { type: 'string', enum: ['all', 'due', 'new'] }
    },
    required: ['filter']
  },
  handler: async (params, ctx) => {
    // return value is sent back to the agent
  }
});
```

### Registering a cron job

```typescript
registerCron({
  schedule: '*/15 * * * *',   // every 15 minutes — nudge checker
  handler: async (ctx) => { ... }
});

registerCron({
  schedule: '0 9 * * 0',     // Sunday 9am — weekly recap
  handler: async (ctx) => { ... }
});
```

### Registering an outgoing message hook

```typescript
registerHook({
  event: 'message:outgoing',
  handler: async (message, ctx) => {
    // message.text — the outgoing message content
    // message.channelId — channel where it was sent
    // Only fires on user outgoing messages, not agent responses
  }
});
```

### Sending a message to a channel

```typescript
ctx.channel.send(channelId, 'You just captured "posit" — want to spend 2 minutes on it?');
```

### Plugin config (`openclaw.plugin.json`)

```json
{
  "name": "words-hunter",
  "version": "1.0.0",
  "description": "Master vocabulary captured by Words Hunter via conversational AI sessions.",
  "entrypoint": "dist/index.js",
  "config": {
    "recap_channel": {
      "type": "string",
      "description": "Channel ID for weekly vocab recap. Defaults to primary channel.",
      "required": false
    }
  }
}
```

---

## Appendix B: Error Codes

All tool operations return `ToolResult<T>` — a TypeScript discriminated union.

```typescript
type ToolResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: ToolError };

type ToolError =
  | { code: 'VAULT_NOT_FOUND';  message: string }
  | { code: 'FILE_NOT_FOUND';   message: string; word: string }
  | { code: 'PARSE_ERROR';      message: string; word?: string }
  | { code: 'WRITE_FAILED';     message: string }
  | { code: 'ALREADY_EDITED';   message: string; word: string }
  | { code: 'VAULT_ESCAPE';     message: string; path: string }
  | { code: 'NaN_SCORE';        message: string; field: string };
```

| Code | Trigger | Agent sees |
|------|---------|------------|
| `VAULT_NOT_FOUND` | `config.json` missing or vault path invalid | "Vault not found. Run Words Hunter and save settings." |
| `FILE_NOT_FOUND` | Word `.md` file deleted between scan and load | "Word page for '{word}' not found. It may have been deleted." |
| `PARSE_ERROR` | `mastery.json` malformed or schema version mismatch | "Run `words-hunter repair` to fix mastery data." |
| `WRITE_FAILED` | Atomic write fails (disk full, permissions) | "Could not save progress. Check disk space." |
| `ALREADY_EDITED` | Page modified between read and write | "Page was modified externally — skipped to avoid overwrite." |
| `VAULT_ESCAPE` | Resolved path is outside vault root | "Invalid vault path detected. Please reconfigure Words Hunter." |
| `NaN_SCORE` | LLM returns malformed/missing score fields | "Couldn't score that — try again?" |

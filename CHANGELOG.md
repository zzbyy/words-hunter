# Changelog

All notable changes to Words Hunter are documented here.

Format: [version] - YYYY-MM-DD

---

## [1.8.0.0] - 2026-03-31

### Added

- **Oxford Learner's Dictionary integration** — primary dictionary source, no API key required. Scrapes the public OALD page to extract:
  - British *and* American English pronunciation (IPA)
  - CEFR level badges (A1–C2) per word and per sense
  - Example sentences + Extra Examples
  - Oxford Collocations Dictionary data (adjective, verb +, etc.)
  - Nearby dictionary words
- **Multi-entry merging** — words with multiple POS entries (e.g., "delegate" noun + verb) are fetched and combined into a single word page
- **Anti-detection resilience** — realistic User-Agent, Accept-Language headers, random 0.5–2.0s jitter between requests, serialized scraping queue
- **Merriam-Webster as fallback** — MW API key is now optional; if configured, MW is tried when Oxford fails. MW results are adapted into the same unified data model.
- **New template variables:** `{{pronunciation-bre}}`, `{{pronunciation-ame}}`, `{{cefr}}`, `{{collocations}}`, `{{nearby-words}}`

### Changed

- **Default template redesigned** — now shows BrE/AmE pronunciation, CEFR level, collocations section, and nearby words. Legacy MW variables (`{{syllables}}`, `{{pronunciation}}`) are replaced.
- **Auto-lookup enabled by default** — new installs get dictionary lookup out of the box (Oxford needs no API key)
- **Settings UI simplified** — Oxford is the default source with no configuration needed. MW API key field moved to a collapsible "Fallback" disclosure section.
- **Template migration** — `seedTemplateIfNeeded` detects old MW-era templates and auto-migrates to the new Oxford format

### Removed

- `{{syllables}}` template variable (Oxford doesn't provide syllable breaks; pronunciation field now shows full IPA)

---

## [1.7.1.0] - 2026-03-31

### Fixed

- **Template variable system** — auto-lookup now fills word pages reliably even after a custom template is saved. The updater previously matched hardcoded strings (`**Syllables:**`, `### 1. () *()*`) that disappeared when users edited the template; it now uses explicit template variables instead.
- **Template auto-migration** — `template.md` is now migrated to the new variable format on every app launch (not only when Settings are saved), so users who rebuild the app without opening Preferences are no longer left with unfilled pages.
- **Migration safety** — the migration heuristic checks for any lookup-time variable (not just `{{syllables}}`), so custom templates using `{{meanings}}` or `{{see-also}}` but not `{{syllables}}` are correctly preserved instead of being clobbered.
- **Empty definitions guard** — `{{meanings}}` is no longer replaced with a blank `---` line when the MW API returns an entry with no definitions.
- **Temp file cleanup** — if the atomic write fails mid-update, the `.tmp` file is now removed rather than left in the words folder.

### Changed

- **Template variable convention** — `template.md` now supports four lookup-time variables in addition to the existing `{{word}}` and `{{date}}`: `{{syllables}}`, `{{pronunciation}}`, `{{meanings}}`, and `{{see-also}}`. Any variable can be omitted to opt out of that section being auto-filled. Existing templates without these variables are migrated to the new default on next launch.

## [Unreleased]

### Added

- **`create_word` tool** — agent can add a word page directly from chat; also powers the new `/hunt <word>` slash command
- **`/hunt <word>` slash command** — send `/hunt ephemeral` in any connected channel to instantly capture a word without the macOS app
- **User-editable word page template** — `.wordshunter/template.md` is seeded on first settings save and opened via **Edit Word Template…** in Preferences. Use `{{word}}` and `{{date}}` placeholders. Both the macOS app and OpenClaw plugin read this file; delete it to reset to the built-in default. No rebuild needed when you change it.

### Changed

- **`scan_vault` + `vault_summary`** now filter out words whose `.md` page has been deleted — no more stale entries confusing the agent after manual deletion. Performance improved: one `readdir()` + Set lookup instead of N `fs.access()` calls (scales to tens of thousands of words)
- **Word page template** removes Obsidian-specific `> [!info]` callout; syllables and pronunciation now rendered as standard Markdown (`# word` heading + bold labels) — works in any Markdown editor
- **`My sentence:` bullet** now has a trailing space (`- `) to form a valid Markdown list item in all editors
- **SetupWindow** removes all "Obsidian Vault" labels → "Words Directory"; works with any folder, any Markdown editor
- **Plugin + app** auto-discover each other's configured words directory via `~/Library/Application Support/WordsHunter/discovery.json` — zero manual config after first setup on either side

### Fixed

- **Auto-lookup now fills word pages** — `WordPageUpdater` was guarding on `> [!info]` callout format but the template uses `**Syllables:**` bold labels; lookup silently aborted on every capture. Guard updated to match the actual template format.
- Deleted word pages no longer appear in agent scans after manual deletion from vault

---

## [1.7.0.0] - 2026-03-29

### Added

- **OpenClaw mastery plugin** (`openclaw-plugin/`) — TypeScript plugin for vocabulary mastery via conversational AI:
  - `scan_vault` — lists due/new/all words from `.wordshunter/mastery.json` (O(1), no per-file scanning)
  - `load_word` — loads a word page and its mastery state
  - `record_mastery` — records a practice session, advances Leitner SRS schedule, writes history, regenerates callout
  - `update_page` — writes agent-generated content (best sentences, graduation) back to word pages
  - `record_sighting` — appends in-the-wild sightings to word pages
  - `vault_summary` — aggregates vault stats for on-demand summaries and weekly recaps
- **Leitner SRS scheduler** (`src/srs/scheduler.ts`) — 5-box system (1d/3d/7d/14d/30d intervals), 85-point mastery threshold
- **File watcher** (`src/watcher.ts`) — chokidar-based watcher enqueues 24h capture nudges to `.wordshunter/pending-nudges.json`; restarts with exponential backoff on crash
- **One-time importer** (`src/importer.ts`) — creates mastery.json entries for untracked word pages on plugin load
- **Sighting hook** (`src/hooks/sighting-hook.ts`) — scans outgoing messages for captured words (word-boundary regex), logs silently
- **SKILL.md** — full mastery conversation flow spec for OpenClaw agents (scoring rubric, SRS logic, session timeout, weekly recap)
- **SCHEMA.md** — complete schema contract between Swift app and TypeScript plugin (mastery.json, config.json, pending-nudges.json, callout format, OpenClaw SDK API)
- **Config bridge** (`Sources/WordsHunterLib/Models/AppSettings.swift`) — macOS app exports `.wordshunter/config.json` on settings save, connecting the Swift capture pipeline to the TS plugin
- **69 unit tests** across 11 test files with synthetic fixtures (Vitest)

### Changed

- `AppSettings.exportConfigBridge()` now called in `SetupWindow.startHunting()` after setup completes

### Fixed

- Plugin file writes now work on iCloud Drive, external volumes, and network-mounted vaults — tmp files were previously written to `os.tmpdir()`, causing EXDEV cross-device rename errors
- Plugin installs correctly in production — `chokidar` (file watcher runtime) was incorrectly listed as a dev dependency and was absent from production installs
- Word inputs validated at tool entry points to prevent malformed LLM values from polluting mastery.json keys
- `loadVaultConfig` now checks vault_path exists on disk — returns clear `VAULT_NOT_FOUND` when vault is moved
- `fireOverdueNudges` checks primary_channel before consuming nudges — nudges no longer silently lost before first user interaction
- Plugin config (`config.json`) is now written atomically — no more corruption if the plugin process is killed mid-write
- `watcher.ts` restart counter resets after 30s stability window instead of immediately — prevents infinite restart loop on startup crash

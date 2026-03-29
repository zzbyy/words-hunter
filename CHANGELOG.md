# Changelog

All notable changes to Words Hunter are documented here.

Format: [version] - YYYY-MM-DD

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

- Atomic tmp file writes now use `path.dirname(target)` instead of `os.tmpdir()` — prevents EXDEV errors on iCloud Drive, external volumes, and network mounts
- `chokidar` moved from `devDependencies` to `dependencies` — was causing production install failures
- Word inputs validated at tool entry points to prevent malformed LLM values from polluting mastery.json keys
- `loadVaultConfig` now checks vault_path exists on disk — returns clear `VAULT_NOT_FOUND` when vault is moved
- `fireOverdueNudges` checks primary_channel before consuming nudges — nudges no longer silently lost before first user interaction
- `persistPrimaryChannel` uses atomic write — prevents config.json corruption on process kill
- `watcher.ts` restart counter resets after 30s stability window instead of immediately — prevents infinite restart loop on startup crash

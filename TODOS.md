# Words Hunter — TODOS

## Deferred from dictionary lookup feature (v1.5)

### Collins Dictionary support
**What:** Scrape Collins Dictionary (collinsdictionary.com) to supplement MW definitions.
**Why:** Richer, more accessible definitions for English learners. Complements MW's formal register.
**Pros:** Two-source definitions are meaningfully better than one.
**Cons:** No official API. HTML scraping is brittle — breaks whenever Collins changes their markup.
**Context:** Collins was in the original feature request but deferred because scraping is fragile. Revisit when/if Collins releases an official API, or when we're willing to maintain a scraper.
**Effort:** M (human) → S (CC+gstack)
**Priority:** P2

---

### Definition caching
**What:** Cache MW definitions locally to avoid re-fetching if the same word is captured again.
**Why:** Prevents wasted API calls against the 1,000/month free tier quota.
**Pros:** Extends free tier effectively for users who capture the same word multiple times.
**Cons:** Cache invalidation, storage management, stale definitions.
**Context:** Not needed for v1.5 since lookup is only triggered on new page creation (.skipped means no fetch). Becomes relevant if we ever fetch on re-capture or add a "refresh definition" command.
**Effort:** S (human) → XS (CC+gstack)
**Priority:** P3

---

### MW API rate limit UX
**What:** Distinguish permanent API failures (403 invalid key, 429 quota exhausted) from retryable failures (network errors, 5xx). On permanent failure, disable lookup for the session and optionally note in the Definition section.
**Why:** With 1,000 calls/month free tier (~33/day), a prolific user can silently exhaust quota. Currently the app will retry quota errors until retries are exhausted, wasting the few remaining calls, and the user sees blank definitions with no explanation.
**Pros:** Makes failure visible and actionable. User knows to check their MW dashboard or upgrade their API plan.
**Cons:** Minor added complexity in DictionaryService HTTP status handling.
**Context:** Currently the plan treats all failures as retryable. HTTP 4xx responses should be classified as permanent and not retried. Consider showing "Definition fetch failed (API quota or key issue)" in the Definition section body on permanent failure — OR keeping the silent failure and documenting the MW quota limit prominently in the Settings UI.
**Effort:** S (human) → XS (CC+gstack)
**Priority:** P2
**Note:** v1.5 implementation should at minimum not retry 4xx responses (already added to plan as obvious fix). The UX for communicating failure is the deferred part.

---

### AXUIElement sentence capture
**What:** Capture the full sentence the word appeared in via AXUIElement, not just the word.
**Why:** Enables context-aware lookups, personalized example sentences, and better corpus collocations.
**Pros:** Transforms the feature from "auto-fill a definition" to a true vocabulary enrichment layer.
**Cons:** AXUIElement access varies by app. Not all apps expose text context.
**Context:** Pairs directly with the `## Context` section in the v1.6 word template — if implemented, auto-fills the Context section instead of requiring the user to paste the sentence manually. Requires significant research into per-app AXUIElement compatibility.
**Effort:** L (human) → M (CC+gstack)
**Priority:** P3

---

### Corpus-based collocations
**What:** Fetch common word pairs (collocations) from a corpus API alongside definitions.
**Why:** Knowing that "acquire" commonly collocates with "knowledge" and "skills" is more useful for vocabulary than a dictionary definition alone.
**Cons:** No obvious free-tier API. Would require a corpus data source.
**Priority:** P3

---

### Claude API integration for personalized examples
**What:** Generate personalized example sentences using Claude API, tailored to the user's reading domain (tech, literature, news).
**Why:** Context-relevant examples strengthen retention far better than generic dictionary examples.
**Cons:** Requires Claude API key, adds cost, raises privacy considerations (words sent to external API).
**Priority:** P3

---

### Silent surprise UX — timing edge case
**What:** When a user opens their Obsidian note immediately after capture (before lookup completes, ~2-7s), they see an empty Definition section and may conclude the feature is broken.
**Why:** The lookup runs in background and populates silently. There's no in-app indicator that a fetch is in-flight.
**Context:** This is an intentional design decision (CEO plan: "silent surprise"). The tradeoff is accepted. If user feedback suggests this causes confusion, consider: (a) writing a placeholder "Fetching definition…" that WordPageUpdater replaces on success/removes on failure, or (b) a subtle menu bar indicator during fetch.
**Priority:** P3 — revisit based on user feedback

---

### Obsidian sync TOCTOU
**What:** Obsidian may write to the .md file between WordPageUpdater's read and atomic replace, causing the update to overwrite Obsidian's in-flight sync.
**Why:** FileManager.replaceItem is atomic at the filesystem level but doesn't use NSFileCoordinator, which Obsidian may use.
**Context:** Extremely unlikely in practice (the race window is ~1ms between read and write). Known limitation of v1.5. Full fix would use NSFileCoordinator for coordinated reads/writes.
**Priority:** P3

---

## OpenClaw integration — agent mastery (v2.0 scope)

See CEO plan: `~/.gstack/projects/zzbyy-words-hunter/ceo-plans/2026-03-29-agent-mastery.md`

### Config bridge — macOS app exports vault config (P1)
**What:** When the user saves settings in Words Hunter, the app also writes `.wordshunter/config.json` to the vault root containing `vault_path` and `words_folder`. The TypeScript OpenClaw plugin reads this file to discover the vault — it has no other way to find it (vault path lives in macOS UserDefaults, inaccessible to Node.js).
**Why:** Without this, the plugin can't locate the vault and no tools work. P1 blocker before any integration can run.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P1
**Completed:** v1.7.0.0 (2026-03-29)

---

### PowerMem evaluation — SRS decision gate (P1 spike, week 1)
**What:** Evaluate the PowerMem OpenClaw plugin before implementing a custom SRS scheduler. Adopt if: (a) TypeScript SDK available, (b) API can drive `next_review` dates from our `.wordshunter/mastery.json` (not PowerMem's own store), (c) Ebbinghaus intervals are configurable. If any condition fails → build custom Leitner scheduler (5 boxes: 1d, 3d, 7d, 14d, 30d).
**Why:** PowerMem may be free complexity elimination. Decision gate is week 1 — do not build scheduler until this check is done.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P1
**Completed:** v1.7.0.0 (2026-03-29) — PowerMem conditions failed (no TS SDK, can't drive our mastery.json). Built custom Leitner scheduler (`src/srs/scheduler.ts`, 5 boxes: 1d/3d/7d/14d/30d).

---

### Session timeout handling in SKILL.md
**What:** Define what happens when the user starts a mastery session and stops replying mid-way. Suggested behavior: after 60 min no reply, agent sends "Session paused — resume with /vocab when you're ready" and saves partial progress to mastery.json.
**Why:** Without a timeout, the session is left hanging and the agent has no graceful exit path.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P2
**Completed:** v1.7.0.0 (2026-03-29) — SKILL.md shipped with 60-min idle timeout and resume flow.

---

### Sighting hook — word-boundary regex
**What:** The sighting detection hook must use `\b{word}\b` (case-insensitive word-boundary regex) when scanning outgoing messages. Without this, "posit" would match inside "positive", "deposition", etc., causing false positive sightings.
**Why:** Substring matches produce junk sightings data. Word-boundary matching is correct.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P1 (implement at sighting-hook.ts creation time)
**Completed:** v1.7.0.0 (2026-03-29) — `sighting-hook.ts` uses `new RegExp('\\b' + escapeRegex(word) + '\\b', 'i')` for all word matches.

---

### NaN score guard in record_mastery
**What:** Before writing to mastery.json, `record_mastery` must validate all score fields are numbers within valid range (0–100). On invalid or missing LLM response: log a warning, skip the score update, and surface an error to the agent for retry.
**Why:** If the LLM returns malformed JSON or missing fields, unchecked math produces `NaN` in mastery.json, corrupting the SRS state permanently.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P1 (implement at record_mastery creation time)
**Completed:** v1.7.0.0 (2026-03-29) — `record_mastery` validates `typeof score === 'number' && score >= 0 && score <= 100`; returns `NaN_SCORE` error on invalid input.

---

### Watcher error handling — chokidar crash recovery
**What:** `watcher.ts` must catch chokidar errors and attempt a restart with exponential backoff. If restart fails 3 times, log a persistent warning to the agent channel so the failure is visible.
**Why:** A silently dead watcher means no 24h nudges fire. The user would never know captures stopped being tracked.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P2
**Completed:** v1.7.0.0 (2026-03-29) — `watcher.ts` has exponential backoff (1s/2s/4s), 3-restart limit, channel alert on permanent failure. Restart counter resets after 30s stability window.

---

### Graduation celebration — LLM response guards
**What:** The graduation LLM call must validate: response is non-empty, contains the graduated word, and is under 200 chars. On failure: retry once, then fall back to a templated message ("You've mastered '{word}'!") rather than sending garbage to the channel.
**Why:** LLMs occasionally refuse, hallucinate off-topic text, or return empty strings. The celebration moment shouldn't break silently.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P2

---

### Vault path traversal validation
**What:** All plugin file operations must verify the resolved path starts with the configured vault root before reading or writing. Throw a `VAULT_ESCAPE` error if any path escapes the vault. Relevant because `.wordshunter/config.json` could theoretically be misconfigured with a path like `../../etc/passwd`.
**Why:** Defense-in-depth. The config is user-controlled but could be corrupted or tampered.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P2
**Completed:** v1.7.0.0 (2026-03-29) — `assertInVault()` in `vault.ts` uses `path.resolve()` then checks `resolvedPath.startsWith(resolvedVault + path.sep)`; called by all 4 write tools.

---

### mastery.json concurrent write race (P1)
**What:** If two sessions score the same word simultaneously (e.g., user opens a second chat window mid-session), both read the same mastery.json state, compute independently, and the second `writeMasteryStore` silently overwrites the first. The earlier session's progress is lost.
**Why:** Atomic rename prevents file corruption but not lost-update races at the application level. With single-user CLI usage this is rare, but it becomes probable when the sighting hook fires during an active session.
**Cons:** Full fix requires a file lock (e.g., `proper-lockfile`) or a read-modify-write CAS loop. Either adds a runtime dependency or retry complexity.
**Context:** Found in adversarial review (v1.7.0.0). Blast radius is small (one session's score lost, next session will re-score), but the failure is silent.
**Effort:** S (human) → XS (CC+gstack)
**Priority:** P1

---

### Sighting hook — serial O(N) writes
**What:** When the user sends a message containing 10 captured words, the sighting hook fires 10 sequential read-modify-write cycles on `sightings.json`. Each is individually safe, but under heavy load (user pastes a paragraph with many vocabulary words) this creates a write storm.
**Why:** Sequential writes are predictable and correct but slow for batch scenarios. A short debounce or batch queue would coalesce writes within a single message into one pass.
**Cons:** Adds batching complexity. Low priority because most messages contain 0-1 matching words.
**Context:** Found in adversarial review (v1.7.0.0). Not a correctness bug, purely a performance concern. Sightings now use centralized `sightings.json` (v2 event-based schema) instead of per-word `.md` files.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P2

---

### Importer — non-word .md file ingestion
**What:** `importer.ts` scans the words folder for all `.md` files and creates mastery entries for each. If the vault contains Obsidian templates, MOCs (Maps of Content), or system files like `_index.md` in the words folder, they get imported as vocabulary words, polluting mastery.json with invalid entries.
**Why:** The importer assumes all `.md` files in the words folder are word pages. A filename filter (e.g., skip files starting with `_` or containing `/`) would prevent accidental ingestion.
**Cons:** Filtering heuristics may miss edge cases. A more robust fix is to check for the `> [!info]` callout that all real word pages contain.
**Context:** Found in adversarial review (v1.7.0.0). Low blast radius — invalid entries have no word page to load_word against, but they pollute scan_vault output.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P2

---

### `words-hunter repair` command — regenerate callouts from JSON
**What:** CLI command that walks `.wordshunter/mastery.json` and regenerates the `> [!mastery]` callout in each `.md` word page from JSON state. Needed when Obsidian sync corrupts or overwrites the derived callout display.
**Why:** The callout is now a derived view — if it drifts from the JSON, the user sees stale data in Obsidian. Repair restores consistency without manual editing.
**Effort:** S (human) → XS (CC+gstack)
**Priority:** P2

---

### README — privacy note for sighting hook
**What:** README must include a privacy section explaining: the sighting hook scans your own outgoing messages locally; only the matched word + timestamp + sentence is stored in `.wordshunter/sightings.json`; nothing is sent to external servers.
**Why:** The hook reads every outgoing message across all connected channels. Users deserve to know this up front.
**Effort:** XS (human) → XS (CC+gstack)
**Priority:** P2 (write before ClawHub publish)

---

## Implementation plan — v1.5 (current sprint)

See CEO plan: `~/.gstack/projects/words-hunter/ceo-plans/2026-03-25-dictionary-lookup.md`

### Implementation sequence (eng review confirmed order)

1. **Package.swift refactor** — split into WordsHunterLib + WordsHunter + WordsHunterTests
2. **AppSettings** — add useWordFolder, lookupEnabled, lookupRetries + migration guard
3. **Keychain wrapper** — mwApiKey (SecItemAdd/SecItemUpdate/SecItemDelete/SecItemCopyMatching)
4. **WordPageCreator** — use wordsFolderURL (DRY fix)
5. **AppDelegate** — extract path from .created (regression fix)
6. **DictionaryService** — MW fetch, Task cancellation, exponential backoff, 4xx handling
7. **WordPageUpdater** — read, whitespace-check, atomic write
8. **SetupWindow NSStackView refactor** — layout refactor only, verify builds
9. **SetupWindow new controls** — subfolder toggle, lookup section, API key field, retry stepper
10. **Tests** — migration guard, wordsFolderURL, JSON parsing, definition body check, regression

### Tests to write
- `AppSettingsTests` — migration guard, wordsFolderURL conditional (true/false/nil), round-trip
- `DictionaryServiceTests` — JSON parsing from MW fixture, 4xx not retried, Task cancellation
- `WordPageUpdaterTests` — definition body whitespace check, abort on edited, abort on missing file
- `WordPageCreatorTests` — uses wordsFolderURL (not inline URL) — regression test
- Regression: AppDelegate path extraction — `.created(path)` path is passed to DictionaryService

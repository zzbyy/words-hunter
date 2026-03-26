# Words Hunter — TODOS

## Deferred from capture animation feature (v1.6)

### Milestone celebrations
**What:** Special animation variant when captured word count hits milestone numbers (10, 25, 50, 100). Firework burst from the pouch, or brief count display in a sparkle cloud.
**Why:** Gives users a sense of long-term progression and rewards consistent use over weeks/months.
**Pros:** High emotional impact; makes the app feel like a game you play over months.
**Cons:** Requires persistent word count (already tracked as `captureCount` in AppSettings from v1.6).
**Context:** The base animation (Magic Lasso Pouch) ships first. Milestones are a natural v2 layer — the infrastructure is already in place via CaptureState. Just add `milestoneTriggered` computed property and a new animation branch in BubbleWindow.
**Effort:** S (human) → XS (CC+gstack)
**Priority:** P2

---

### Custom sound design
**What:** Replace system sounds (Pop/Tink) with purpose-designed audio: a soft lasso swish for the snap, a gentle poof for the bubble phase, a small chime when the word reaches the pouch.
**Why:** Sound is ~50% of the wow factor. Custom sounds make the animation feel designed rather than assembled from system components.
**Cons:** Requires bundling audio assets (.caf or .aiff) or using AudioToolbox synthesis. Adds to app bundle size.
**Context:** The base animation uses `NSSound(named: "Pop")`. Sound timing is already wired to fire at Phase 2 snap (350ms). Adding custom sounds is a pure swap — just change the NSSound source. Hardest part is producing quality audio assets.
**Effort:** M (human: ~2 days for audio design) → S (CC: 15min for integration, audio design is the constraint)
**Priority:** P2

---

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
**Context:** This is part of the v3 vision in the CEO plan. Requires significant research into per-app AXUIElement compatibility.
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

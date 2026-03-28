# Changelog

All notable changes to Words Hunter are documented here.

## [1.7.0.0] - 2026-03-28

### Added
- **Lemmatization**: Captured inflected forms ("has", "consolidates", "running") now resolve to their base forms ("Have", "Consolidate", "Run") using NLTagger(.lemma). Proper nouns and acronyms ("API") fall back to original casing
- **10-section production-first template**: New vocabulary page format ordered for active production use — Pronunciation → Definition → Useful Frames → Collocations → Examples → Use It → Synonyms → Related Words → Word Family → Memory Hook. Research-backed ordering (Tinkham 1993, Barcroft 2004)
- **"Use It" section**: The key section for converting passive recognition to active command — one self-produced sentence
- **Auto-fill POS in header**: Part of speech (`{POS}` placeholder) auto-replaced from MW `fl` field on lookup
- **Auto-fill Pronunciation**: MW pronunciation notation (`hwi.prs[0].mw`) written to `## Pronunciation` after lookup
- **Vault-scan Related Words**: After lookup, existing vault pages whose names appear in the definition text are written as `[[backlinks]]` to `## Related Words`. Grows smarter as your vault grows. Only runs when "Use word folder" is enabled
- **KeychainHelper**: Thin macOS Keychain wrapper for secure API key storage

### Changed
- `WordPageUpdater` generalized from single-section to multi-section updater — all four auto-fills happen in one atomic read→transform→write
- `DictionaryContent` struct extended with `partOfSpeech`, `pronunciation`, `relatedWords` fields (all optional/defaulted — backward compatible)
- `parseMWResponse` simplified — takes first 2 entries × first shortdef each
- `TextCapture.lemmatize` simplified to single NLTagger call with capitalized output
- `BubbleWindow` uses spring animation (`CASpringAnimation`) for smoother entrance

### Removed
- `VaultScanner.swift` — logic consolidated into `DictionaryService.vaultScanRelatedWords()`
- YAML frontmatter from vocabulary template (replaced by markdown header)
- `TextCapture.warmUp()` and complex singularization helpers
- MW format code stripping (no longer extracting vis examples)

## [1.6.1.0] - 2026-03-27

### Fixed
- Bubble shadow and rectangular artifact issues
- Move shadow layer setup from draw() to init()

## [1.5.0.0] - 2026-03-25

### Added
- Dictionary lookup: Merriam-Webster Collegiate API auto-fills the Definition section after page creation
- Subfolder toggle: word pages can be saved in a dedicated subfolder (e.g. Words/) or vault root
- Keychain storage for MW API key
- Exponential backoff retry (1–5 retries, configurable)
- Permanent 4xx failure detection (no retry on 401/403/429)

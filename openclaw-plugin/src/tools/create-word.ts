import fs from 'node:fs/promises';
import path from 'node:path';
import { ToolResult, VaultConfig, ok, err } from '../types.js';
import { wordsFolderPath, validateWord, assertInVault } from '../vault.js';
import { masteryJsonPath, readMasteryStore, writeMasteryStore } from '../vault.js';
import { todayString } from '../srs/scheduler.js';
import { cambridgeLookup, CambridgeBlockedError } from '../cambridge-lookup.js';
import { fillWordPage } from '../fill-word-page.js';

// Template variable reference:
//   Creation-time (filled on page creation):  {{word}}, {{date}}
//   Lookup-time   (filled after Cambridge):   {{syllables}}, {{pronunciation}}, {{meanings}},
//                                              {{when-to-use}}, {{word-family}}, {{see-also}}
//
// Lookup runs immediately after page creation (best-effort, 8s timeout).
// If lookup fails, template vars remain as placeholders for the agent to fill.
// Any variable can be omitted from a custom template to opt out of that section.
const DEFAULT_TEMPLATE = `# {{word}}

**Syllables:** {{syllables}} · **Pronunciation:** {{pronunciation}}

## Sightings
- {{date}} — *(context sentence where you saw the word)*

---

## Meanings
{{meanings}}

## When to Use
{{when-to-use}}
---

## Word Family
{{word-family}}
---

## See Also
{{see-also}}

---

## Memory Tip
*(optional: etymology, mnemonic, personal association — anything that helps you remember)*`;

async function loadTemplate(config: VaultConfig, word: string, date: string): Promise<string> {
  const templatePath = path.join(config.vault_path, '.wordshunter', 'template.md');
  let raw = DEFAULT_TEMPLATE;
  try {
    const custom = await fs.readFile(templatePath, 'utf8');
    if (custom.trim()) raw = custom;
  } catch { /* file missing — use default */ }
  return raw
    .replaceAll('{{word}}', word)
    .replaceAll('{{date}}', date);
}

export type LookupStatus = 'ok' | 'not_found' | 'blocked' | 'failed';

/**
 * create_word — create a new word page, register it for study, and auto-fill
 * dictionary data from Cambridge Dictionary.
 *
 * The page is created and returned immediately. Cambridge lookup runs in the
 * same call (best-effort, 8s timeout). On lookup failure the page is still
 * created with template placeholders — the agent can fill them later via
 * the Enrich step in SKILL.md.
 */
export async function createWord(
  config: VaultConfig,
  params: { word: string },
): Promise<ToolResult<{ word: string; path: string; lookup: LookupStatus }>> {
  const validationError = validateWord(params.word);
  if (validationError) return err(validationError);

  const word = params.word.toLowerCase().trim();
  const wordsDir = wordsFolderPath(config);
  const filePath = path.join(wordsDir, `${word}.md`);

  const escapeError = assertInVault(config.vault_path, filePath);
  if (escapeError) return err(escapeError);

  // Check if already exists
  try {
    await fs.access(filePath);
    return err({ code: 'FILE_EXISTS', message: `Word page for '${word}' already exists.` });
  } catch { /* doesn't exist — proceed */ }

  // Create the words folder if needed
  await fs.mkdir(wordsDir, { recursive: true });

  // Load template from .wordshunter/template.md, fall back to hardcoded default
  const today = todayString();
  const template = await loadTemplate(config, word, today);

  const tmp = path.join(wordsDir, `.wh-create-${Date.now()}.md.tmp`);
  try {
    await fs.writeFile(tmp, template, 'utf8');
    await fs.rename(tmp, filePath);
  } catch (e) {
    try { await fs.unlink(tmp); } catch { /* best effort */ }
    return err({ code: 'WRITE_FAILED', message: `Could not create word page: ${String(e)}` });
  }

  // Register in mastery.json (box=1, status=new)
  const jsonPath = masteryJsonPath(config);
  const storeResult = await readMasteryStore(jsonPath);
  if (storeResult.ok) {
    const store = storeResult.data;
    if (!store.words[word]) {
      store.words[word] = {
        word,
        box: 1,
        status: 'learning',
        score: 0,
        last_practiced: '',
        next_review: today,
        sessions: 0,
        failures: [],
        best_sentences: [],
      };
      await writeMasteryStore(jsonPath, store);
    }
  }

  // Cambridge lookup — best-effort, fills template vars in-place
  const lookup = await runLookup(config, word);

  return ok({ word, path: filePath, lookup });
}

async function runLookup(config: VaultConfig, word: string): Promise<LookupStatus> {
  try {
    const content = await cambridgeLookup(word);
    if (!content) return 'not_found';
    await fillWordPage(config, word, content);
    return 'ok';
  } catch (e) {
    if (e instanceof CambridgeBlockedError) return 'blocked';
    return 'failed';
  }
}

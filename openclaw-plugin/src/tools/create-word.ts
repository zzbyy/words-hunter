import fs from 'node:fs/promises';
import path from 'node:path';
import { ToolResult, VaultConfig, ok, err } from '../types.js';
import { wordsFolderPath, validateWord, assertInVault } from '../vault.js';
import { masteryJsonPath, readMasteryStore, writeMasteryStore } from '../vault.js';
import { todayString } from '../srs/scheduler.js';

const DEFAULT_TEMPLATE = `# {{word}}

**Syllables:** *(e.g. po·sit)* · **Pronunciation:** *(e.g. /ˈpɒz.ɪt/)*

## Sightings
- {{date}} — *(context sentence where you saw the word)*

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

*(list related forms, each with a short example)*

---

## See Also
*(link to other captured words with a note on how they differ)*

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

/**
 * create_word — create a new word page and add it to mastery.json.
 *
 * Writes a blank word page template to the words folder and registers
 * the word in mastery.json (box=1, status=new). Returns FILE_EXISTS if
 * the page already exists.
 */
export async function createWord(
  config: VaultConfig,
  params: { word: string },
): Promise<ToolResult<{ word: string; path: string }>> {
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

  return ok({ word, path: filePath });
}

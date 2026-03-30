import fs from 'node:fs/promises';
import path from 'node:path';
import { ToolResult, VaultConfig, ScannedWord, ScanFilter, ok, err } from '../types.js';
import { masteryJsonPath, wordsFolderPath, readMasteryStore } from '../vault.js';
import { isDue, todayString } from '../srs/scheduler.js';

/**
 * scan_vault — list words matching a filter.
 *
 * Reads from mastery.json (O(1), not O(N .md files)).
 * filter=new: words with .md files NOT yet in mastery.json.
 * filter=due: words in mastery.json where next_review <= today.
 * filter=all: all words in mastery.json.
 */
export async function scanVault(
  config: VaultConfig,
  filter: ScanFilter,
  today: string = todayString(),
): Promise<ToolResult<ScannedWord[]>> {
  const jsonPath = masteryJsonPath(config);
  const storeResult = await readMasteryStore(jsonPath);
  if (!storeResult.ok) return storeResult;
  const store = storeResult.data;

  if (filter === 'new') {
    // Words with .md pages that have no mastery entry
    const wordsDir = wordsFolderPath(config);
    let files: string[];
    try {
      files = await fs.readdir(wordsDir);
    } catch {
      return ok([]);  // words folder empty or missing — no new words
    }
    const newWords: ScannedWord[] = files
      .filter(f => f.endsWith('.md'))
      .map(f => path.basename(f, '.md').toLowerCase())
      .filter(word => !store.words[word])
      .map(word => ({ word, status: 'new' as const, next_review: null }));
    return ok(newWords);
  }

  // Filter out words whose .md page has been deleted.
  // One readdir() builds a Set — O(1) lookup per word instead of N fs.access() calls.
  const wordsDir = wordsFolderPath(config);
  let existingFiles: Set<string>;
  try {
    const files = await fs.readdir(wordsDir);
    existingFiles = new Set(files.filter(f => f.endsWith('.md')).map(f => f.toLowerCase()));
  } catch {
    existingFiles = new Set(); // words folder missing — treat all as deleted
  }
  const entries = Object.values(store.words).filter(
    e => existingFiles.has(`${e.word.toLowerCase()}.md`)
  );

  if (filter === 'due') {
    const due = entries
      .filter(e => isDue(e, today))
      .map(e => ({ word: e.word, status: e.status, next_review: e.next_review }));
    return ok(due);
  }

  // filter === 'all'
  const all = entries.map(e => ({
    word: e.word,
    status: e.status,
    next_review: e.next_review,
  }));
  return ok(all);
}

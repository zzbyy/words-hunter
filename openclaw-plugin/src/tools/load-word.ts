import fs from 'node:fs/promises';
import path from 'node:path';
import { ToolResult, VaultConfig, WordEntry, ok, err } from '../types.js';
import { masteryJsonPath, wordsFolderPath, assertInVault, readMasteryStore, validateWord } from '../vault.js';

export interface LoadWordResult {
  word: string;
  content: string;            // raw .md file content
  mastery: WordEntry | null;  // null = word exists but has never been practiced
}

/**
 * load_word — load a word page + its mastery state.
 *
 * Returns FILE_NOT_FOUND if the .md page doesn't exist.
 * Returns mastery=null if the word has no mastery.json entry (new word).
 */
export async function loadWord(
  config: VaultConfig,
  word: string,
): Promise<ToolResult<LoadWordResult>> {
  const inputErr = validateWord(word);
  if (inputErr) return { ok: false, error: inputErr };

  const wordLower = word.toLowerCase();
  const wordsDir = wordsFolderPath(config);
  const mdPath = path.join(wordsDir, `${wordLower}.md`);

  // Path traversal check
  const escapeErr = assertInVault(config.vault_path, mdPath);
  if (escapeErr) return { ok: false, error: escapeErr };

  // Read .md file
  let content: string;
  try {
    content = await fs.readFile(mdPath, 'utf8');
  } catch (e: unknown) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code === 'ENOENT') {
      return err({ code: 'FILE_NOT_FOUND', message: `Word page '${wordLower}.md' not found.`, word: wordLower });
    }
    return err({ code: 'FILE_NOT_FOUND', message: `Could not read '${wordLower}.md': ${String(e)}`, word: wordLower });
  }

  // Read mastery state
  const jsonPath = masteryJsonPath(config);
  const storeResult = await readMasteryStore(jsonPath);
  if (!storeResult.ok) return storeResult;
  const mastery = storeResult.data.words[wordLower] ?? null;

  return ok({ word: wordLower, content, mastery });
}

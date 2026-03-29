import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import { ToolResult, VaultConfig, ok, err } from '../types.js';
import { wordsFolderPath, assertInVault, validateWord } from '../vault.js';

export interface UpdatePageInput {
  word: string;
  best_sentence?: string;         // append to ### Best Sentences
  graduation_sentence?: string;   // write ## Graduation section (first time only)
  content_hash?: string;          // ALREADY_EDITED guard: MD5 of content when last read
}

/**
 * update_page — write agent-generated content back to a word .md page.
 *
 * Handles:
 * - Best Sentences: append to existing list (creates section if absent)
 * - Graduation: write ## Graduation section (no-op if already present)
 * - ALREADY_EDITED guard: if content_hash provided and page has changed, abort
 * - VAULT_ESCAPE: rejects paths outside vault root
 */
export async function updatePage(
  config: VaultConfig,
  input: UpdatePageInput,
): Promise<ToolResult<void>> {
  const wordErr = validateWord(input.word);
  if (wordErr) return { ok: false, error: wordErr };

  const wordLower = input.word.toLowerCase();
  const wordsDir = wordsFolderPath(config);
  const mdPath = path.join(wordsDir, `${wordLower}.md`);

  const escapeErr = assertInVault(config.vault_path, mdPath);
  if (escapeErr) return { ok: false, error: escapeErr };

  let content: string;
  try {
    content = await fs.readFile(mdPath, 'utf8');
  } catch (e: unknown) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code === 'ENOENT') {
      return err({ code: 'FILE_NOT_FOUND', message: `Word page '${wordLower}.md' not found.`, word: wordLower });
    }
    return err({ code: 'WRITE_FAILED', message: `Could not read '${wordLower}.md': ${String(e)}` });
  }

  // ALREADY_EDITED guard
  if (input.content_hash) {
    const currentHash = md5(content);
    if (currentHash !== input.content_hash) {
      return err({ code: 'ALREADY_EDITED', message: `Page '${wordLower}.md' was modified externally. Skipped to avoid overwrite.`, word: wordLower });
    }
  }

  let updated = content;

  // Append Best Sentence
  if (input.best_sentence) {
    const today = new Date().toISOString().slice(0, 10);
    const line = `- ${today}: "${input.best_sentence}"`;
    const sectionRegex = /^### Best Sentences\n/m;
    if (sectionRegex.test(updated)) {
      updated = updated.replace(sectionRegex, `### Best Sentences\n${line}\n`);
    } else {
      updated += `\n\n### Best Sentences\n${line}\n`;
    }
  }

  // Write ## Graduation section (idempotent)
  if (input.graduation_sentence && !/^## Graduation/m.test(updated)) {
    const today = new Date().toISOString().slice(0, 10);
    updated += `\n\n## Graduation\n> On ${today} you mastered this word. "${input.graduation_sentence}"\n`;
  }

  if (updated === content) return ok(undefined);  // nothing changed

  // Write atomically
  const tmp = path.join(
    path.dirname(mdPath),
    `.wh-update-${wordLower}-${Date.now()}-${Math.random().toString(36).slice(2)}.tmp`,
  );
  try {
    await fs.writeFile(tmp, updated, 'utf8');
    await fs.rename(tmp, mdPath);
  } catch (e) {
    try { await fs.unlink(tmp); } catch { /* best effort */ }
    return err({ code: 'WRITE_FAILED', message: `Could not write '${wordLower}.md': ${String(e)}` });
  }

  return ok(undefined);
}

/** MD5 hash of a string — used for ALREADY_EDITED guard. */
export function md5(content: string): string {
  return crypto.createHash('md5').update(content, 'utf8').digest('hex');
}

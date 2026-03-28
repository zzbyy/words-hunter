import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { ToolResult, VaultConfig, ok, err } from '../types.js';
import { wordsFolderPath, assertInVault } from '../vault.js';

export interface RecordSightingInput {
  word: string;
  sentence: string;
  channel?: string;   // optional channel label, e.g. "Telegram — work chat"
}

/**
 * record_sighting — append a sighting to ## Sightings in the word page.
 *
 * Sightings are logged for visibility only — SRS score is still controlled
 * by explicit record_mastery calls. A duplicate sighting is benign.
 */
export async function recordSighting(
  config: VaultConfig,
  input: RecordSightingInput,
): Promise<ToolResult<void>> {
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

  const today = new Date().toISOString().slice(0, 10);
  const channelNote = input.channel ? ` *(${input.channel})*` : '';
  const line = `- ${today} — "${input.sentence}"${channelNote}`;

  // Append to ## Sightings section (creates it if absent)
  let updated: string;
  const sightingsRegex = /^## Sightings\n/m;
  if (sightingsRegex.test(content)) {
    updated = content.replace(sightingsRegex, `## Sightings\n${line}\n`);
  } else {
    // Insert at the top of the page, after the > [!info] block
    const infoEndRegex = /^(> \[!info\][^\n]*\n(?:>[^\n]*\n)*)/m;
    const match = infoEndRegex.exec(content);
    if (match) {
      const insertAt = match.index + match[0].length;
      updated =
        content.slice(0, insertAt) +
        `\n## Sightings\n${line}\n\n---\n` +
        content.slice(insertAt);
    } else {
      updated = `## Sightings\n${line}\n\n---\n\n` + content;
    }
  }

  const tmp = path.join(os.tmpdir(), `wh-sighting-${wordLower}-${Date.now()}.md`);
  try {
    await fs.writeFile(tmp, updated, 'utf8');
    await fs.rename(tmp, mdPath);
  } catch (e) {
    try { await fs.unlink(tmp); } catch { /* best effort */ }
    return err({ code: 'WRITE_FAILED', message: `Could not write '${wordLower}.md': ${String(e)}` });
  }

  return ok(undefined);
}

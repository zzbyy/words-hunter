import fs from 'node:fs/promises';
import { ToolResult, VaultConfig, VaultSummary, ok } from '../types.js';
import { masteryJsonPath, wordsFolderPath, readMasteryStore } from '../vault.js';
import { isDue, todayString } from '../srs/scheduler.js';

/**
 * vault_summary — aggregate stats across the vault.
 *
 * Reads mastery.json only (fast). Used for weekly recap and on-demand /vocab command.
 */
export async function vaultSummary(
  config: VaultConfig,
  today: string = todayString(),
): Promise<ToolResult<VaultSummary>> {
  const jsonPath = masteryJsonPath(config);
  const storeResult = await readMasteryStore(jsonPath);
  if (!storeResult.ok) return storeResult;
  const store = storeResult.data;

  // Only count words whose .md page still exists on disk.
  // One readdir() + Set lookup instead of N fs.access() calls.
  const wordsDir = wordsFolderPath(config);
  let existingFiles: Set<string>;
  try {
    const files = await fs.access(wordsDir).then(() => fs.readdir(wordsDir));
    existingFiles = new Set(files.filter(f => f.endsWith('.md')).map(f => f.toLowerCase()));
  } catch {
    existingFiles = new Set();
  }
  const entries = Object.values(store.words).filter(
    e => existingFiles.has(`${e.word.toLowerCase()}.md`)
  );

  let mastered = 0;
  let reviewing = 0;
  let learning = 0;
  let due_today = 0;
  let lastSession: string | null = null;

  for (const e of entries) {
    if (e.status === 'mastered') mastered++;
    else if (e.status === 'reviewing') reviewing++;
    else learning++;

    if (isDue(e, today)) due_today++;

    if (e.last_practiced) {
      if (!lastSession || e.last_practiced > lastSession) {
        lastSession = e.last_practiced;
      }
    }
  }

  return ok({
    total: entries.length,
    mastered,
    reviewing,
    learning,
    due_today,
    last_session: lastSession,
  });
}

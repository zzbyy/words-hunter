import fs from 'node:fs/promises';
import path from 'node:path';
import { ToolResult, ToolError, VaultConfig, MasteryStore, NudgeQueue, ok, err } from './types.js';

// ============================================================
// Config loading
// ============================================================

export async function loadVaultConfig(vaultRoot: string): Promise<ToolResult<VaultConfig>> {
  const configPath = path.join(vaultRoot, '.wordshunter', 'config.json');
  let raw: string;
  try {
    raw = await fs.readFile(configPath, 'utf8');
  } catch {
    return err({ code: 'VAULT_NOT_FOUND', message: `config.json not found at ${configPath}. Run Words Hunter and save settings.` });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return err({ code: 'PARSE_ERROR', message: `config.json is not valid JSON` });
  }

  if (typeof parsed !== 'object' || parsed === null) {
    return err({ code: 'PARSE_ERROR', message: 'config.json must be a JSON object' });
  }
  const obj = parsed as Record<string, unknown>;
  if (typeof obj['vault_path'] !== 'string' || !obj['vault_path']) {
    return err({ code: 'VAULT_NOT_FOUND', message: 'config.json is missing vault_path' });
  }

  const vaultPath = obj['vault_path'] as string;
  try {
    await fs.access(vaultPath);
  } catch {
    return err({ code: 'VAULT_NOT_FOUND', message: `vault_path '${vaultPath}' does not exist on disk. Has the vault been moved?` });
  }

  return ok({
    vault_path: vaultPath,
    words_folder: typeof obj['words_folder'] === 'string' ? obj['words_folder'] : '',
  });
}

// ============================================================
// Input validation
// ============================================================

/** Valid word: letters, digits, apostrophes, hyphens, spaces — max 50 chars. */
const WORD_PATTERN = /^[a-z0-9][a-z0-9'\- ]{0,49}$/i;

/**
 * Validate that a word string from LLM tool input is safe to use as a file
 * name and mastery.json key. Rejects path traversal, empty strings, and
 * excessively long values before any I/O occurs.
 */
export function validateWord(word: string): ToolError | null {
  if (!word || typeof word !== 'string') {
    return { code: 'INVALID_INPUT', message: 'word must be a non-empty string', field: 'word' };
  }
  if (!WORD_PATTERN.test(word)) {
    return { code: 'INVALID_INPUT', message: `Invalid word format: '${word}'. Words must contain only letters, digits, apostrophes, hyphens, and spaces (max 50 chars).`, field: 'word' };
  }
  return null;
}

// ============================================================
// Path helpers
// ============================================================

export function wordsFolderPath(config: VaultConfig): string {
  return config.words_folder
    ? path.join(config.vault_path, config.words_folder)
    : config.vault_path;
}

export function masteryJsonPath(config: VaultConfig): string {
  return path.join(config.vault_path, '.wordshunter', 'mastery.json');
}

export function nudgeQueuePath(config: VaultConfig): string {
  return path.join(config.vault_path, '.wordshunter', 'pending-nudges.json');
}

/** Returns VAULT_ESCAPE if resolvedPath is not inside vaultRoot. */
export function assertInVault(
  vaultRoot: string,
  resolvedPath: string,
): ToolError | null {
  const vaultResolved = path.resolve(vaultRoot);
  const fileResolved = path.resolve(resolvedPath);
  if (!fileResolved.startsWith(vaultResolved + path.sep) && fileResolved !== vaultResolved) {
    return { code: 'VAULT_ESCAPE', message: `Path escapes vault root`, path: resolvedPath };
  }
  return null;
}

// ============================================================
// mastery.json I/O
// ============================================================

export async function readMasteryStore(jsonPath: string): Promise<ToolResult<MasteryStore>> {
  let raw: string;
  try {
    raw = await fs.readFile(jsonPath, 'utf8');
  } catch (e: unknown) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code === 'ENOENT') {
      // First run — no mastery data yet, return empty store
      return ok({ version: 1, words: {} });
    }
    return err({ code: 'PARSE_ERROR', message: `Could not read mastery.json: ${String(e)}` });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return err({ code: 'PARSE_ERROR', message: 'mastery.json is not valid JSON. Run words-hunter repair.' });
  }

  if (
    typeof parsed !== 'object' ||
    parsed === null ||
    (parsed as MasteryStore).version !== 1 ||
    typeof (parsed as MasteryStore).words !== 'object'
  ) {
    return err({ code: 'PARSE_ERROR', message: 'mastery.json has unexpected schema. Run words-hunter repair.' });
  }

  return ok(parsed as MasteryStore);
}

export async function writeMasteryStore(
  jsonPath: string,
  store: MasteryStore,
): Promise<ToolResult<void>> {
  const dir = path.dirname(jsonPath);
  const tmp = path.join(dir, `.wh-mastery-${Date.now()}-${Math.random().toString(36).slice(2)}.json.tmp`);
  try {
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(tmp, JSON.stringify(store, null, 2), 'utf8');
    await fs.rename(tmp, jsonPath);
    return ok(undefined);
  } catch (e) {
    try { await fs.unlink(tmp); } catch { /* best effort */ }
    return err({ code: 'WRITE_FAILED', message: `Could not write mastery.json: ${String(e)}` });
  }
}

// ============================================================
// pending-nudges.json I/O
// ============================================================

export async function readNudgeQueue(queuePath: string): Promise<NudgeQueue> {
  try {
    const raw = await fs.readFile(queuePath, 'utf8');
    const parsed = JSON.parse(raw) as NudgeQueue;
    return parsed;
  } catch {
    return { version: 1, nudges: [] };
  }
}

export async function writeNudgeQueue(
  queuePath: string,
  queue: NudgeQueue,
): Promise<ToolResult<void>> {
  const dir = path.dirname(queuePath);
  const tmp = path.join(dir, `.wh-nudges-${Date.now()}-${Math.random().toString(36).slice(2)}.json.tmp`);
  try {
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(tmp, JSON.stringify(queue, null, 2), 'utf8');
    await fs.rename(tmp, queuePath);
    return ok(undefined);
  } catch (e) {
    try { await fs.unlink(tmp); } catch { /* best effort */ }
    return err({ code: 'WRITE_FAILED', message: `Could not write pending-nudges.json: ${String(e)}` });
  }
}

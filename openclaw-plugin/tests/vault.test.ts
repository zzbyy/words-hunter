import { describe, it, expect } from 'vitest';
import { loadVaultConfig, readNudgeQueue, writeNudgeQueue } from '../src/vault.js';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function makeTmpDir(): Promise<{ dir: string; cleanup: () => Promise<void> }> {
  const dir = await mkdtemp(join(tmpdir(), 'wh-vault-test-'));
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

// ─── loadVaultConfig ────────────────────────────────────────────────────────

describe('loadVaultConfig', () => {
  it('missing config.json → VAULT_NOT_FOUND', async () => {
    const { dir, cleanup } = await makeTmpDir();
    try {
      const result = await loadVaultConfig(dir);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('VAULT_NOT_FOUND');
    } finally {
      await cleanup();
    }
  });

  it('malformed JSON → PARSE_ERROR', async () => {
    const { dir, cleanup } = await makeTmpDir();
    try {
      await mkdir(join(dir, '.wordshunter'), { recursive: true });
      await writeFile(join(dir, '.wordshunter', 'config.json'), 'not json{{{', 'utf8');
      const result = await loadVaultConfig(dir);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('PARSE_ERROR');
    } finally {
      await cleanup();
    }
  });

  it('missing vault_path → VAULT_NOT_FOUND', async () => {
    const { dir, cleanup } = await makeTmpDir();
    try {
      await mkdir(join(dir, '.wordshunter'), { recursive: true });
      await writeFile(
        join(dir, '.wordshunter', 'config.json'),
        JSON.stringify({ words_folder: 'Words' }),
        'utf8',
      );
      const result = await loadVaultConfig(dir);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('VAULT_NOT_FOUND');
    } finally {
      await cleanup();
    }
  });

  it('valid config → returns VaultConfig', async () => {
    const { dir, cleanup } = await makeTmpDir();
    // Create a second tmp dir to serve as the vault_path (must exist on disk now)
    const { dir: vaultDir, cleanup: cleanupVault } = await makeTmpDir();
    try {
      await mkdir(join(dir, '.wordshunter'), { recursive: true });
      await writeFile(
        join(dir, '.wordshunter', 'config.json'),
        JSON.stringify({ vault_path: vaultDir, words_folder: 'Words' }),
        'utf8',
      );
      const result = await loadVaultConfig(dir);
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.vault_path).toBe(vaultDir);
        expect(result.data.words_folder).toBe('Words');
      }
    } finally {
      await cleanup();
      await cleanupVault();
    }
  });

  it('config without words_folder → defaults to empty string', async () => {
    const { dir, cleanup } = await makeTmpDir();
    const { dir: vaultDir, cleanup: cleanupVault } = await makeTmpDir();
    try {
      await mkdir(join(dir, '.wordshunter'), { recursive: true });
      await writeFile(
        join(dir, '.wordshunter', 'config.json'),
        JSON.stringify({ vault_path: vaultDir }),
        'utf8',
      );
      const result = await loadVaultConfig(dir);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.data.words_folder).toBe('');
    } finally {
      await cleanup();
      await cleanupVault();
    }
  });

  it('vault_path does not exist on disk → VAULT_NOT_FOUND', async () => {
    const { dir, cleanup } = await makeTmpDir();
    try {
      await mkdir(join(dir, '.wordshunter'), { recursive: true });
      await writeFile(
        join(dir, '.wordshunter', 'config.json'),
        JSON.stringify({ vault_path: '/nonexistent/vault/path' }),
        'utf8',
      );
      const result = await loadVaultConfig(dir);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('VAULT_NOT_FOUND');
    } finally {
      await cleanup();
    }
  });
});

// ─── nudge queue I/O ────────────────────────────────────────────────────────

describe('nudge queue I/O', () => {
  it('readNudgeQueue on missing file → empty queue', async () => {
    const { dir, cleanup } = await makeTmpDir();
    try {
      const queue = await readNudgeQueue(join(dir, 'pending-nudges.json'));
      expect(queue.version).toBe(1);
      expect(queue.nudges).toEqual([]);
    } finally {
      await cleanup();
    }
  });

  it('writeNudgeQueue + readNudgeQueue round-trip', async () => {
    const { dir, cleanup } = await makeTmpDir();
    try {
      const queuePath = join(dir, 'pending-nudges.json');
      const written = { version: 1 as const, nudges: [{ word: 'posit', nudge_due_at: '2026-03-30T09:00:00Z' }] };
      const writeResult = await writeNudgeQueue(queuePath, written);
      expect(writeResult.ok).toBe(true);

      const read = await readNudgeQueue(queuePath);
      expect(read.nudges).toHaveLength(1);
      expect(read.nudges[0].word).toBe('posit');
    } finally {
      await cleanup();
    }
  });
});

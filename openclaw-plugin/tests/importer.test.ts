import { describe, it, expect } from 'vitest';
import { importUntracked } from '../src/importer.js';
import type { VaultConfig, MasteryStore } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function makeVault(): Promise<{ vaultPath: string; config: VaultConfig; cleanup: () => Promise<void> }> {
  const vaultPath = await mkdtemp(join(tmpdir(), 'wh-import-test-'));
  await mkdir(join(vaultPath, '.wordshunter'), { recursive: true });
  await mkdir(join(vaultPath, 'Words'), { recursive: true });
  const config: VaultConfig = { vault_path: vaultPath, words_folder: 'Words' };
  return { vaultPath, config, cleanup: () => rm(vaultPath, { recursive: true, force: true }) };
}

describe('importUntracked', () => {
  it('empty words folder → imports nothing', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await importUntracked(config);
      expect(result.imported).toEqual([]);
    } finally {
      await cleanup();
    }
  });

  it('word page not in mastery.json → gets imported', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      await writeFile(join(vaultPath, 'Words', 'posit.md'), '# posit', 'utf8');
      await writeFile(join(vaultPath, 'Words', 'ephemeral.md'), '# ephemeral', 'utf8');

      const result = await importUntracked(config);
      expect(result.imported.sort()).toEqual(['ephemeral', 'posit']);

      // verify mastery.json was written
      const { readMasteryStore } = await import('../src/vault.js');
      const { masteryJsonPath } = await import('../src/vault.js');
      const store = await readMasteryStore(masteryJsonPath(config));
      expect(store.ok).toBe(true);
      if (store.ok) {
        expect(store.data.words['posit'].box).toBe(1);
        expect(store.data.words['posit'].status).toBe('learning');
        expect(store.data.words['posit'].sessions).toBe(0);
      }
    } finally {
      await cleanup();
    }
  });

  it('existing mastery.json entry → not overwritten', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      await writeFile(join(vaultPath, 'Words', 'posit.md'), '# posit', 'utf8');
      const store: MasteryStore = {
        version: 1,
        words: {
          posit: { word: 'posit', box: 3, status: 'reviewing', score: 78, last_practiced: '2026-03-28', next_review: '2026-04-05', sessions: 4, failures: [], best_sentences: [] },
        },
      };
      await writeFile(join(vaultPath, '.wordshunter', 'mastery.json'), JSON.stringify(store), 'utf8');

      const result = await importUntracked(config);
      expect(result.imported).toEqual([]);  // posit already tracked, nothing imported
    } finally {
      await cleanup();
    }
  });

  it('words folder missing → returns empty (graceful)', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      // Remove the words folder
      await rm(join(vaultPath, 'Words'), { recursive: true, force: true });
      const result = await importUntracked(config);
      expect(result.imported).toEqual([]);
    } finally {
      await cleanup();
    }
  });

  it('non-.md files in words folder are ignored', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      await writeFile(join(vaultPath, 'Words', 'posit.md'), '# posit', 'utf8');
      await writeFile(join(vaultPath, 'Words', '.DS_Store'), '', 'utf8');
      await writeFile(join(vaultPath, 'Words', 'notes.txt'), 'notes', 'utf8');

      const result = await importUntracked(config);
      expect(result.imported).toEqual(['posit']);
    } finally {
      await cleanup();
    }
  });
});

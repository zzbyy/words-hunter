import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { scanVault } from '../src/tools/scan-vault.js';
import type { VaultConfig, MasteryStore } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function makeVault(): Promise<{ vaultPath: string; config: VaultConfig; cleanup: () => Promise<void> }> {
  const vaultPath = await mkdtemp(join(tmpdir(), 'wh-test-'));
  await mkdir(join(vaultPath, '.wordshunter'), { recursive: true });
  await mkdir(join(vaultPath, 'Words'), { recursive: true });
  const config: VaultConfig = { vault_path: vaultPath, words_folder: 'Words' };
  return { vaultPath, config, cleanup: () => rm(vaultPath, { recursive: true, force: true }) };
}

async function writeMasteryStore(vaultPath: string, store: MasteryStore): Promise<void> {
  await writeFile(join(vaultPath, '.wordshunter', 'mastery.json'), JSON.stringify(store, null, 2), 'utf8');
}

const TODAY = '2026-03-29';

describe('scan_vault', () => {
  it('missing mastery.json → returns empty list (first-run case)', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await scanVault(config, 'all');
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.data).toEqual([]);
    } finally {
      await cleanup();
    }
  });

  it('filter=all → returns all words in mastery.json', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const store: MasteryStore = {
        version: 1,
        words: {
          posit: { word: 'posit', box: 3, status: 'reviewing', score: 78, last_practiced: '2026-03-28', next_review: '2026-04-05', sessions: 4, failures: [], best_sentences: [] },
          ephemeral: { word: 'ephemeral', box: 1, status: 'learning', score: 0, last_practiced: '', next_review: TODAY, sessions: 0, failures: [], best_sentences: [] },
        },
      };
      await writeMasteryStore(vaultPath, store);
      // .md files must exist for words to be included
      await writeFile(join(vaultPath, 'Words', 'posit.md'), '# posit', 'utf8');
      await writeFile(join(vaultPath, 'Words', 'ephemeral.md'), '# ephemeral', 'utf8');
      const result = await scanVault(config, 'all');
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toHaveLength(2);
        expect(result.data.map(w => w.word).sort()).toEqual(['ephemeral', 'posit']);
      }
    } finally {
      await cleanup();
    }
  });

  it('filter=due → only words where next_review ≤ today', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const store: MasteryStore = {
        version: 1,
        words: {
          posit: { word: 'posit', box: 3, status: 'reviewing', score: 78, last_practiced: '2026-03-28', next_review: '2026-04-05', sessions: 4, failures: [], best_sentences: [] },
          ephemeral: { word: 'ephemeral', box: 1, status: 'learning', score: 0, last_practiced: '', next_review: TODAY, sessions: 0, failures: [], best_sentences: [] },
        },
      };
      await writeMasteryStore(vaultPath, store);
      // .md files must exist for words to be included
      await writeFile(join(vaultPath, 'Words', 'posit.md'), '# posit', 'utf8');
      await writeFile(join(vaultPath, 'Words', 'ephemeral.md'), '# ephemeral', 'utf8');
      // Pass TODAY explicitly so the test isn't sensitive to the system clock
      const result = await scanVault(config, 'due', TODAY);
      expect(result.ok).toBe(true);
      if (result.ok) {
        const words = result.data.map(w => w.word);
        expect(words).toContain('ephemeral');
        // posit's next_review (2026-04-05) is after today (2026-03-29)
        expect(words).not.toContain('posit');
      }
    } finally {
      await cleanup();
    }
  });

  it('filter=new → words with .md files not in mastery.json', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      // Write .md files
      await writeFile(join(vaultPath, 'Words', 'posit.md'), '# posit', 'utf8');
      await writeFile(join(vaultPath, 'Words', 'ephemeral.md'), '# ephemeral', 'utf8');
      // mastery.json has only 'posit'
      const store: MasteryStore = {
        version: 1,
        words: {
          posit: { word: 'posit', box: 1, status: 'learning', score: 0, last_practiced: '', next_review: TODAY, sessions: 0, failures: [], best_sentences: [] },
        },
      };
      await writeMasteryStore(vaultPath, store);
      const result = await scanVault(config, 'new');
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toHaveLength(1);
        expect(result.data[0].word).toBe('ephemeral');
        expect(result.data[0].status).toBe('new');
      }
    } finally {
      await cleanup();
    }
  });

  it('malformed mastery.json → PARSE_ERROR', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      await writeFile(join(vaultPath, '.wordshunter', 'mastery.json'), 'not valid json{{{', 'utf8');
      const result = await scanVault(config, 'all');
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('PARSE_ERROR');
    } finally {
      await cleanup();
    }
  });

  it('words folder empty → filter=new returns empty list', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await scanVault(config, 'new');
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.data).toEqual([]);
    } finally {
      await cleanup();
    }
  });
});

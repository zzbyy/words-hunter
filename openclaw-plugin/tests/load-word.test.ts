import { describe, it, expect } from 'vitest';
import { loadWord } from '../src/tools/load-word.js';
import type { VaultConfig, MasteryStore } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';

const FIXTURES = join(import.meta.dirname, 'fixtures');

async function makeVault(): Promise<{ vaultPath: string; config: VaultConfig; cleanup: () => Promise<void> }> {
  const vaultPath = await mkdtemp(join(tmpdir(), 'wh-test-'));
  await mkdir(join(vaultPath, '.wordshunter'), { recursive: true });
  await mkdir(join(vaultPath, 'Words'), { recursive: true });
  const config: VaultConfig = { vault_path: vaultPath, words_folder: 'Words' };
  return { vaultPath, config, cleanup: () => rm(vaultPath, { recursive: true, force: true }) };
}

describe('load_word', () => {
  it('returns content + null mastery for new word (no mastery.json entry)', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      const result = await loadWord(config, 'posit');
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.word).toBe('posit');
        expect(result.data.content).toBe(mdContent);
        expect(result.data.mastery).toBeNull();
      }
    } finally {
      await cleanup();
    }
  });

  it('returns content + mastery state when mastery.json entry exists', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-full-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      const store: MasteryStore = {
        version: 1,
        words: {
          posit: { word: 'posit', box: 3, status: 'reviewing', score: 78, last_practiced: '2026-03-29', next_review: '2026-04-05', sessions: 4, failures: ["confused with 'postulate'"], best_sentences: [] },
        },
      };
      await writeFile(join(vaultPath, '.wordshunter', 'mastery.json'), JSON.stringify(store), 'utf8');

      const result = await loadWord(config, 'posit');
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.mastery?.box).toBe(3);
        expect(result.data.mastery?.status).toBe('reviewing');
        expect(result.data.mastery?.failures).toEqual(["confused with 'postulate'"]);
      }
    } finally {
      await cleanup();
    }
  });

  it('missing .md file → FILE_NOT_FOUND', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await loadWord(config, 'nonexistent');
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error.code).toBe('FILE_NOT_FOUND');
        expect((result.error as { word: string }).word).toBe('nonexistent');
      }
    } finally {
      await cleanup();
    }
  });
});

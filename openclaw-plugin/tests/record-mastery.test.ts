import { describe, it, expect } from 'vitest';
import { recordMastery } from '../src/tools/record-mastery.js';
import type { VaultConfig, MasteryStore } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile, readFile } from 'node:fs/promises';
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

describe('record_mastery', () => {
  it('creates mastery.json if it does not exist (first word practiced)', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      const result = await recordMastery(config, { word: 'posit', score: 88 });
      expect(result.ok).toBe(true);

      const storeRaw = await readFile(join(vaultPath, '.wordshunter', 'mastery.json'), 'utf8');
      const store: MasteryStore = JSON.parse(storeRaw);
      expect(store.words['posit']).toBeDefined();
      expect(store.words['posit'].box).toBe(2);  // box 1 + success → 2
      expect(store.words['posit'].sessions).toBe(1);
    } finally {
      await cleanup();
    }
  });

  it('writes mastery.json atomically (file is valid JSON after write)', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      await recordMastery(config, { word: 'posit', score: 90 });
      const raw = await readFile(join(vaultPath, '.wordshunter', 'mastery.json'), 'utf8');
      expect(() => JSON.parse(raw)).not.toThrow();
    } finally {
      await cleanup();
    }
  });

  it('rejects NaN score → NaN_SCORE error', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await recordMastery(config, { word: 'posit', score: NaN });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('NaN_SCORE');
    } finally {
      await cleanup();
    }
  });

  it('box 4+ → graduated flag true', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      // Set up existing state at box 3
      const store: MasteryStore = {
        version: 1,
        words: {
          posit: { word: 'posit', box: 3, status: 'reviewing', score: 78, last_practiced: '2026-03-28', next_review: '2026-03-29', sessions: 3, failures: [], best_sentences: [] },
        },
      };
      await writeFile(join(vaultPath, '.wordshunter', 'mastery.json'), JSON.stringify(store), 'utf8');

      const result = await recordMastery(config, { word: 'posit', score: 90 });
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.graduated).toBe(true);
        expect(result.data.box).toBe(4);
        expect(result.data.status).toBe('mastered');
      }
    } finally {
      await cleanup();
    }
  });

  it('appends History line to .md page', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      await recordMastery(config, { word: 'posit', score: 88 });
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      expect(updated).toContain('### History');
      expect(updated).toContain('box 1→2');
    } finally {
      await cleanup();
    }
  });

  it('regenerates callout in .md page', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      await recordMastery(config, { word: 'posit', score: 88 });
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      expect(updated).toContain('> [!mastery]');
    } finally {
      await cleanup();
    }
  });

  it('best_sentence saved when score >= mastery threshold', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const mdContent = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), mdContent, 'utf8');

      await recordMastery(config, { word: 'posit', score: 88, best_sentence: 'I posit that the sky is blue.' });
      const raw = await readFile(join(vaultPath, '.wordshunter', 'mastery.json'), 'utf8');
      const store: MasteryStore = JSON.parse(raw);
      expect(store.words['posit'].best_sentences).toHaveLength(1);
      expect(store.words['posit'].best_sentences[0].text).toBe('I posit that the sky is blue.');
    } finally {
      await cleanup();
    }
  });
});

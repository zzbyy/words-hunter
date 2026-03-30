import { describe, it, expect } from 'vitest';
import { vaultSummary } from '../src/tools/vault-summary.js';
import type { VaultConfig, MasteryStore } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function makeVault(): Promise<{ vaultPath: string; config: VaultConfig; cleanup: () => Promise<void> }> {
  const vaultPath = await mkdtemp(join(tmpdir(), 'wh-test-'));
  await mkdir(join(vaultPath, '.wordshunter'), { recursive: true });
  const config: VaultConfig = { vault_path: vaultPath, words_folder: 'Words' };
  return { vaultPath, config, cleanup: () => rm(vaultPath, { recursive: true, force: true }) };
}

const TODAY = '2026-03-29';

describe('vault_summary', () => {
  it('empty vault → all zeros, last_session null', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await vaultSummary(config);
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.total).toBe(0);
        expect(result.data.mastered).toBe(0);
        expect(result.data.last_session).toBeNull();
      }
    } finally {
      await cleanup();
    }
  });

  it('aggregates totals correctly', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const store: MasteryStore = {
        version: 1,
        words: {
          posit:     { word: 'posit',     box: 4, status: 'mastered',  score: 90, last_practiced: '2026-03-29', next_review: '2026-04-12', sessions: 5, failures: [], best_sentences: [] },
          ephemeral: { word: 'ephemeral', box: 3, status: 'reviewing', score: 75, last_practiced: '2026-03-28', next_review: '2026-04-05', sessions: 3, failures: [], best_sentences: [] },
          liminal:   { word: 'liminal',   box: 1, status: 'learning',  score: 55, last_practiced: '2026-03-27', next_review: TODAY,        sessions: 1, failures: [], best_sentences: [] },
          nascent:   { word: 'nascent',   box: 2, status: 'learning',  score: 0,  last_practiced: '',           next_review: TODAY,        sessions: 0, failures: [], best_sentences: [] },
        },
      };
      await writeFile(join(vaultPath, '.wordshunter', 'mastery.json'), JSON.stringify(store), 'utf8');
      // .md files must exist for words to be counted
      await mkdir(join(vaultPath, 'Words'), { recursive: true });
      for (const word of Object.keys(store.words)) {
        await writeFile(join(vaultPath, 'Words', `${word}.md`), `# ${word}`, 'utf8');
      }

      const result = await vaultSummary(config, TODAY);
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.total).toBe(4);
        expect(result.data.mastered).toBe(1);
        expect(result.data.reviewing).toBe(1);
        expect(result.data.learning).toBe(2);
        expect(result.data.due_today).toBe(2);  // liminal + nascent due today
        expect(result.data.last_session).toBe('2026-03-29');  // most recent
      }
    } finally {
      await cleanup();
    }
  });
});

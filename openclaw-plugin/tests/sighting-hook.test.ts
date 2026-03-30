import { describe, it, expect, vi, afterEach } from 'vitest';
import { onOutgoingMessage } from '../src/hooks/sighting-hook.js';
import type { VaultConfig, MasteryStore } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function makeVault(words: string[]): Promise<{ vaultPath: string; config: VaultConfig; cleanup: () => Promise<void> }> {
  const vaultPath = await mkdtemp(join(tmpdir(), 'wh-test-'));
  await mkdir(join(vaultPath, '.wordshunter'), { recursive: true });
  await mkdir(join(vaultPath, 'Words'), { recursive: true });
  const config: VaultConfig = { vault_path: vaultPath, words_folder: 'Words' };

  // Write .md files for each word
  for (const word of words) {
    await writeFile(join(vaultPath, 'Words', `${word}.md`), `> [!info] ${word}\n> //\n\n## Sightings\n`, 'utf8');
  }

  // Write mastery.json
  const storeWords: MasteryStore['words'] = {};
  for (const word of words) {
    storeWords[word] = { word, box: 1, status: 'learning', score: 0, last_practiced: '', next_review: '2026-03-29', sessions: 0, failures: [], best_sentences: [] };
  }
  const store: MasteryStore = { version: 1, words: storeWords };
  await writeFile(join(vaultPath, '.wordshunter', 'mastery.json'), JSON.stringify(store), 'utf8');

  return { vaultPath, config, cleanup: () => rm(vaultPath, { recursive: true, force: true }) };
}

describe('sighting-hook', () => {
  it('outgoing message containing "posit" → sighting recorded', async () => {
    const { vaultPath, config, cleanup } = await makeVault(['posit']);
    try {
      await onOutgoingMessage(config, 'I posit that this is correct.', 'Telegram');
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      expect(updated).toContain('I posit that this is correct.');
    } finally {
      await cleanup();
    }
  });

  it('outgoing message containing "positive" → no sighting for "posit" (word-boundary regex)', async () => {
    const { vaultPath, config, cleanup } = await makeVault(['posit']);
    try {
      const originalContent = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      await onOutgoingMessage(config, 'That is a positive outcome!');
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      // File should be unchanged — no sighting recorded
      expect(updated).toBe(originalContent);
    } finally {
      await cleanup();
    }
  });

  it('message containing both "posit" and "ephemeral" → two sightings recorded', async () => {
    const { vaultPath, config, cleanup } = await makeVault(['posit', 'ephemeral']);
    try {
      await onOutgoingMessage(config, 'I posit that ephemeral fame is overrated.', 'WeChat');
      const positContent = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      const ephemeralContent = await readFile(join(vaultPath, 'Words', 'ephemeral.md'), 'utf8');
      expect(positContent).toContain('I posit that ephemeral fame is overrated.');
      expect(ephemeralContent).toContain('I posit that ephemeral fame is overrated.');
    } finally {
      await cleanup();
    }
  });

  it('message matching no words → no-op (no errors)', async () => {
    const { config, cleanup } = await makeVault(['posit']);
    try {
      // Should not throw
      await expect(onOutgoingMessage(config, 'This message has no captured words.')).resolves.toBeUndefined();
    } finally {
      await cleanup();
    }
  });
});

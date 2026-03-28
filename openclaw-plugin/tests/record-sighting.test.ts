import { describe, it, expect } from 'vitest';
import { recordSighting } from '../src/tools/record-sighting.js';
import type { VaultConfig } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';

const FIXTURES = join(import.meta.dirname, 'fixtures');

async function makeVault(): Promise<{ vaultPath: string; config: VaultConfig; cleanup: () => Promise<void> }> {
  const vaultPath = await mkdtemp(join(tmpdir(), 'wh-test-'));
  await mkdir(join(vaultPath, 'Words'), { recursive: true });
  const config: VaultConfig = { vault_path: vaultPath, words_folder: 'Words' };
  return { vaultPath, config, cleanup: () => rm(vaultPath, { recursive: true, force: true }) };
}

describe('record_sighting', () => {
  it('appends sighting to existing ## Sightings section', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const initial = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), initial, 'utf8');

      await recordSighting(config, { word: 'posit', sentence: 'I posit that this works.', channel: 'Telegram' });
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      expect(updated).toContain('I posit that this works.');
      expect(updated).toContain('*(Telegram)*');
    } finally {
      await cleanup();
    }
  });

  it('creates ## Sightings section if absent', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      // Minimal page with no Sightings section
      const initial = '> [!info] posit\n> //\n\n## Meanings\n\n> to put forward';
      await writeFile(join(vaultPath, 'Words', 'posit.md'), initial, 'utf8');

      await recordSighting(config, { word: 'posit', sentence: 'I posit this.' });
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      expect(updated).toContain('## Sightings');
      expect(updated).toContain('I posit this.');
    } finally {
      await cleanup();
    }
  });

  it('missing .md file → FILE_NOT_FOUND', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await recordSighting(config, { word: 'ghost', sentence: 'test' });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('FILE_NOT_FOUND');
    } finally {
      await cleanup();
    }
  });
});

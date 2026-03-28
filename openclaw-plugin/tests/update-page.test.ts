import { describe, it, expect } from 'vitest';
import { updatePage, md5 } from '../src/tools/update-page.js';
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

describe('update_page', () => {
  it('appends Best Sentence without overwriting existing ones', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const initial = readFileSync(join(FIXTURES, 'posit-full-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), initial, 'utf8');

      await updatePage(config, { word: 'posit', best_sentence: 'Scientists posit that light is a wave.' });
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      // New sentence added
      expect(updated).toContain('Scientists posit that light is a wave.');
      // Original sentence preserved
      expect(updated).toContain('I posit that dark matter exists.');
    } finally {
      await cleanup();
    }
  });

  it('ALREADY_EDITED guard: aborts if content changed since last read', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const initial = '# posit\n\nSome content.';
      await writeFile(join(vaultPath, 'Words', 'posit.md'), initial, 'utf8');

      const staleHash = md5('different content');  // hash doesn't match
      const result = await updatePage(config, { word: 'posit', best_sentence: 'New sentence.', content_hash: staleHash });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('ALREADY_EDITED');
    } finally {
      await cleanup();
    }
  });

  it('ALREADY_EDITED guard: proceeds if hash matches', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const initial = '# posit\n\nSome content.';
      await writeFile(join(vaultPath, 'Words', 'posit.md'), initial, 'utf8');

      const correctHash = md5(initial);
      const result = await updatePage(config, { word: 'posit', best_sentence: 'New sentence.', content_hash: correctHash });
      expect(result.ok).toBe(true);
    } finally {
      await cleanup();
    }
  });

  it('VAULT_ESCAPE: rejects paths outside vault root', async () => {
    const { config, cleanup } = await makeVault();
    try {
      // Patch config to use a path-traversal word name (this would be sanitized upstream,
      // but test that the vault escape check catches it if it slips through)
      const evilConfig: VaultConfig = { ...config, words_folder: '../../../etc' };
      const result = await updatePage(evilConfig, { word: 'passwd', best_sentence: 'evil' });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('VAULT_ESCAPE');
    } finally {
      await cleanup();
    }
  });

  it('writes ## Graduation section (first time only)', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const initial = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), initial, 'utf8');

      await updatePage(config, { word: 'posit', graduation_sentence: 'Scientists posit that dark matter exists.' });
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      expect(updated).toContain('## Graduation');
      expect(updated).toContain('Scientists posit that dark matter exists.');
    } finally {
      await cleanup();
    }
  });

  it('Graduation section is not written twice (idempotent)', async () => {
    const { vaultPath, config, cleanup } = await makeVault();
    try {
      const initial = readFileSync(join(FIXTURES, 'posit-graduation.md'), 'utf8');
      await writeFile(join(vaultPath, 'Words', 'posit.md'), initial, 'utf8');

      // Already has ## Graduation — should be no-op
      await updatePage(config, { word: 'posit', graduation_sentence: 'A second graduation sentence.' });
      const updated = await readFile(join(vaultPath, 'Words', 'posit.md'), 'utf8');
      // Original graduation still there
      expect(updated).toContain('Scientists posit that the universe is expanding');
      // New one not added
      expect(updated).not.toContain('A second graduation sentence.');
      // Only one Graduation section
      const count = (updated.match(/^## Graduation/mg) ?? []).length;
      expect(count).toBe(1);
    } finally {
      await cleanup();
    }
  });

  it('missing .md file → FILE_NOT_FOUND', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const result = await updatePage(config, { word: 'ghost', best_sentence: 'never' });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error.code).toBe('FILE_NOT_FOUND');
    } finally {
      await cleanup();
    }
  });
});

import { describe, it, expect } from 'vitest';
import { fillWordPage } from '../src/fill-word-page.js';
import type { CambridgeContent } from '../src/cambridge-lookup.js';
import type { VaultConfig } from '../src/types.js';
import { mkdtemp, rm, mkdir, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function makeVault(): Promise<{ config: VaultConfig; cleanup: () => Promise<void> }> {
  const vaultPath = await mkdtemp(join(tmpdir(), 'wh-fill-test-'));
  await mkdir(join(vaultPath, 'Words'), { recursive: true });
  const config: VaultConfig = { vault_path: vaultPath, words_folder: 'Words' };
  return { config, cleanup: () => rm(vaultPath, { recursive: true, force: true }) };
}

const SAMPLE_CONTENT: CambridgeContent = {
  headword: 'pos·it',
  pronunciationBrE: '/ˈpɒz.ɪt/',
  pronunciationAmE: '/ˈpɑː.zɪt/',
  entries: [
    {
      pos: 'verb',
      senses: [
        {
          cefrLevel: 'C2',
          definition: 'to suggest that something is true',
          examples: ['Scientists posit that the universe began with a big bang.'],
          senseLabel: null,
          grammar: '[T]',
          patterns: [],
          register: null,
        },
      ],
    },
  ],
  corpusExamples: ['These findings posit a new direction for research in this field.'],
  wordFamily: [
    { word: 'posit', partsOfSpeech: ['verb', 'noun'] },
    { word: 'position', partsOfSpeech: ['noun', 'verb'] },
  ],
};

const TEMPLATE = `# posit

**Syllables:** {{syllables}} · **Pronunciation:** {{pronunciation}}

## Sightings
- 2026-04-01 — *(context sentence)*

---

## Meanings
{{meanings}}

## When to Use
{{when-to-use}}
---

## Word Family
{{word-family}}
---

## See Also
{{see-also}}

---

## Memory Tip
*(optional)*`;

describe('fillWordPage', () => {
  it('fills syllables and pronunciation', async () => {
    const { config, cleanup } = await makeVault();
    try {
      await writeFile(join(config.vault_path, 'Words', 'posit.md'), TEMPLATE, 'utf8');
      await fillWordPage(config, 'posit', SAMPLE_CONTENT);
      const result = await readFile(join(config.vault_path, 'Words', 'posit.md'), 'utf8');
      expect(result).toContain('pos·it');
      expect(result).toContain('BrE /ˈpɒz.ɪt/ · AmE /ˈpɑː.zɪt/');
      expect(result).not.toContain('{{syllables}}');
      expect(result).not.toContain('{{pronunciation}}');
    } finally {
      await cleanup();
    }
  });

  it('fills meanings with definition and bolded lemma', async () => {
    const { config, cleanup } = await makeVault();
    try {
      await writeFile(join(config.vault_path, 'Words', 'posit.md'), TEMPLATE, 'utf8');
      await fillWordPage(config, 'posit', SAMPLE_CONTENT);
      const result = await readFile(join(config.vault_path, 'Words', 'posit.md'), 'utf8');
      expect(result).toContain('to suggest that something is true');
      expect(result).toContain('**posit**');  // bolded lemma in example
      expect(result).not.toContain('{{meanings}}');
    } finally {
      await cleanup();
    }
  });

  it('fills word family entries', async () => {
    const { config, cleanup } = await makeVault();
    try {
      await writeFile(join(config.vault_path, 'Words', 'posit.md'), TEMPLATE, 'utf8');
      await fillWordPage(config, 'posit', SAMPLE_CONTENT);
      const result = await readFile(join(config.vault_path, 'Words', 'posit.md'), 'utf8');
      expect(result).toContain('**posit**');
      expect(result).toContain('**position**');
      expect(result).not.toContain('{{word-family}}');
    } finally {
      await cleanup();
    }
  });

  it('fills see-also with vault wikilinks', async () => {
    const { config, cleanup } = await makeVault();
    try {
      // Add a known word in the vault that appears in the definition corpus
      await writeFile(join(config.vault_path, 'Words', 'suggest.md'), '# suggest', 'utf8');
      await writeFile(join(config.vault_path, 'Words', 'posit.md'), TEMPLATE, 'utf8');
      await fillWordPage(config, 'posit', SAMPLE_CONTENT);
      const result = await readFile(join(config.vault_path, 'Words', 'posit.md'), 'utf8');
      expect(result).toContain('[[suggest]]');
      expect(result).not.toContain('{{see-also}}');
    } finally {
      await cleanup();
    }
  });

  it('falls back to no-related-words note when vault is empty', async () => {
    const { config, cleanup } = await makeVault();
    try {
      await writeFile(join(config.vault_path, 'Words', 'posit.md'), TEMPLATE, 'utf8');
      await fillWordPage(config, 'posit', SAMPLE_CONTENT);
      const result = await readFile(join(config.vault_path, 'Words', 'posit.md'), 'utf8');
      expect(result).toContain('*(no related words found yet)*');
    } finally {
      await cleanup();
    }
  });

  it('returns no_vars when page has no template variables', async () => {
    const { config, cleanup } = await makeVault();
    try {
      await writeFile(join(config.vault_path, 'Words', 'posit.md'), '# posit\n\nAlready filled.', 'utf8');
      const status = await fillWordPage(config, 'posit', SAMPLE_CONTENT);
      expect(status).toBe('no_vars');
    } finally {
      await cleanup();
    }
  });

  it('returns no_vars when file does not exist', async () => {
    const { config, cleanup } = await makeVault();
    try {
      const status = await fillWordPage(config, 'missing', SAMPLE_CONTENT);
      expect(status).toBe('no_vars');
    } finally {
      await cleanup();
    }
  });
});

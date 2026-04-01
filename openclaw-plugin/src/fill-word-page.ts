/**
 * fill-word-page.ts
 *
 * Fills lookup-time template variables in a word page after Cambridge lookup.
 * Ported from WordPageUpdater.swift.
 *
 * Variables filled:
 *   {{syllables}}     — headword (Cambridge shows dot-separated syllables in .headword)
 *   {{pronunciation}} — "BrE /x/ · AmE /y/" or whichever is available
 *   {{meanings}}      — numbered sense blocks with grammar, patterns, examples
 *   {{when-to-use}}   — register/domain labels per sense
 *   {{word-family}}   — related word forms from the Cambridge word family box
 *   {{see-also}}      — [[wikilinks]] for known vault words appearing in definitions
 *
 * Safety: aborts silently if the file is gone or has no lookup-time vars.
 * Writes atomically via tmp file + rename.
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import type { CambridgeContent, CambridgeEntry, CambridgeSense } from './cambridge-lookup.js';
import type { VaultConfig } from './types.js';
import { wordsFolderPath } from './vault.js';

/** All template variables this filler can handle. */
const LOOKUP_VARS = [
  '{{syllables}}',
  '{{pronunciation}}',
  '{{meanings}}',
  '{{when-to-use}}',
  '{{word-family}}',
  '{{see-also}}',
];

/**
 * Fill template variables in a word's .md page with Cambridge lookup data.
 * Returns 'ok' | 'not_found' | 'no_vars' | 'write_failed'.
 */
export async function fillWordPage(
  config: VaultConfig,
  word: string,
  content: CambridgeContent,
): Promise<'ok' | 'no_vars' | 'write_failed'> {
  const wordsDir = wordsFolderPath(config);
  const filePath = path.join(wordsDir, `${word}.md`);

  let text: string;
  try {
    text = await fs.readFile(filePath, 'utf8');
  } catch {
    return 'no_vars'; // file deleted between create and fill — skip silently
  }

  const hasVars = LOOKUP_VARS.some((v) => text.includes(v));
  if (!hasVars) return 'no_vars';

  // Scan vault for related words (for {{see-also}})
  const relatedWords = await scanVaultForRelated(config, content, word);

  let updated = text;

  // {{syllables}} — headword from Cambridge (may include · dots)
  if (updated.includes('{{syllables}}')) {
    updated = updated.replaceAll('{{syllables}}', content.headword);
  }

  // {{pronunciation}} — "BrE /x/ · AmE /y/"
  if (updated.includes('{{pronunciation}}')) {
    const parts: string[] = [];
    if (content.pronunciationBrE) parts.push(`BrE ${content.pronunciationBrE}`);
    if (content.pronunciationAmE) parts.push(`AmE ${content.pronunciationAmE}`);
    const pron = parts.length > 0 ? parts.join(' · ') : '—';
    updated = updated.replaceAll('{{pronunciation}}', pron);
  }

  // {{meanings}} — sense blocks
  if (updated.includes('{{meanings}}')) {
    const meaningsBlock = buildMeaningsBlock(content, word);
    updated = updated.replaceAll('{{meanings}}', meaningsBlock);
  }

  // {{when-to-use}} — register/domain labels
  if (updated.includes('{{when-to-use}}')) {
    updated = updated.replaceAll('{{when-to-use}}', buildWhenToUseBlock(content));
  }

  // {{word-family}} — related word forms
  if (updated.includes('{{word-family}}')) {
    updated = updated.replaceAll('{{word-family}}', buildWordFamilyBlock(content));
  }

  // {{see-also}} — vault wikilinks
  if (updated.includes('{{see-also}}')) {
    const seeAlso =
      relatedWords.length > 0
        ? relatedWords.map((w) => `- [[${w}]]`).join('\n')
        : '*(no related words found yet)*';
    updated = updated.replaceAll('{{see-also}}', seeAlso);
  }

  // Atomic write
  const dir = path.dirname(filePath);
  const tmp = path.join(dir, `.wh-fill-${Date.now()}.md.tmp`);
  try {
    await fs.writeFile(tmp, updated, 'utf8');
    await fs.rename(tmp, filePath);
    return 'ok';
  } catch (e) {
    try { await fs.unlink(tmp); } catch { /* best effort */ }
    return 'write_failed';
  }
}

// ─── Meanings block ───────────────────────────────────────────────────────────

function buildMeaningsBlock(content: CambridgeContent, lemma: string): string {
  const allSenses: Array<[CambridgeEntry, CambridgeSense]> = content.entries.flatMap(
    (entry) => entry.senses.map((s): [CambridgeEntry, CambridgeSense] => [entry, s]),
  );
  if (allSenses.length === 0) return '*(no definitions found)*';

  const blocks: string[] = [];
  for (const [entry, sense] of allSenses) {
    let heading = sense.definition;
    if (sense.grammar) heading += ` · ${sense.grammar}`;
    if (sense.cefrLevel) heading += ` · ${sense.cefrLevel}`;

    // Prefix with POS if available
    const posPrefix = entry.pos ? `**${entry.pos}** — ` : '';

    let block = `\n### ${posPrefix}${heading}\n\n`;

    if (sense.patterns.length > 0) {
      block += '- **Patterns**:\n';
      for (const pattern of sense.patterns) {
        block += `  - \`${pattern}\`\n`;
      }
    }

    for (const example of sense.examples) {
      block += `- ${boldLemma(example, lemma)}\n`;
    }

    blocks.push(block);
  }

  return blocks.join('\n---\n') + '\n\n---\n';
}

// ─── When to use block ────────────────────────────────────────────────────────

function buildWhenToUseBlock(content: CambridgeContent): string {
  const seen = new Set<string>();
  const labels: string[] = [];
  for (const entry of content.entries) {
    for (const sense of entry.senses) {
      if (sense.register && !seen.has(sense.register.toLowerCase())) {
        seen.add(sense.register.toLowerCase());
        labels.push(sense.register);
      }
    }
  }

  if (labels.length > 0) {
    return `**Register:** ${labels.join(', ')}\n`;
  }
  return '**Where it fits:**\n**In casual speech:**\n';
}

// ─── Word family block ────────────────────────────────────────────────────────

function buildWordFamilyBlock(content: CambridgeContent): string {
  if (content.wordFamily.length === 0) {
    return '*(no word family data found — add related forms manually)*\n';
  }
  return (
    content.wordFamily
      .map((entry) => {
        const pos =
          entry.partsOfSpeech.length > 0
            ? ` — ${entry.partsOfSpeech.join(', ')}`
            : '';
        return `- **${entry.word}**${pos}`;
      })
      .join('\n') + '\n'
  );
}

// ─── See Also — vault scanner ─────────────────────────────────────────────────

/**
 * Scan the vault for words that appear in the content's definitions/examples.
 * Returns word filenames (without .md) that are already in the vault.
 */
async function scanVaultForRelated(
  config: VaultConfig,
  content: CambridgeContent,
  excludeWord: string,
): Promise<string[]> {
  const wordsDir = wordsFolderPath(config);
  let files: string[];
  try {
    files = await fs.readdir(wordsDir);
  } catch {
    return [];
  }

  const vaultWords = files
    .filter((f) => f.endsWith('.md') && !f.startsWith('.'))
    .map((f) => f.slice(0, -3).toLowerCase())
    .filter((w) => w !== excludeWord.toLowerCase());

  if (vaultWords.length === 0) return [];

  // Build a corpus from definitions and examples
  const allSenses = content.entries.flatMap((e) => e.senses);
  const corpus = [
    ...allSenses.map((s) => s.definition),
    ...allSenses.flatMap((s) => s.examples),
  ]
    .join(' ')
    .toLowerCase();

  const related: string[] = [];
  for (const vw of vaultWords) {
    const regex = new RegExp(`\\b${escapeRegex(vw)}\\b`, 'i');
    if (regex.test(corpus)) related.push(vw);
  }
  return related;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function boldLemma(text: string, lemma: string): string {
  if (!lemma) return text;
  const escaped = escapeRegex(lemma);
  return text.replace(new RegExp(`\\b(${escaped}\\w*)`, 'gi'), '**$1**');
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  parseContent,
  extractHeadword,
  extractPronunciations,
  extractEntries,
  extractCorpusExamples,
  extractWordFamily,
} from '../src/cambridge-lookup.js';
import { load } from 'cheerio';

const FIXTURES = join(import.meta.dirname, 'fixtures');

function loadFixture(name: string): string {
  return readFileSync(join(FIXTURES, name), 'utf8');
}

describe('cambridge-lookup — posit fixture', () => {
  const html = loadFixture('cambridge-posit.html');

  it('parseContent returns a valid CambridgeContent', () => {
    const content = parseContent(html, 'posit');
    expect(content).not.toBeNull();
    expect(content!.headword).toBe('pos·it');
  });

  it('extractHeadword returns dot-separated syllables', () => {
    const $ = load(html);
    expect(extractHeadword($)).toBe('pos·it');
  });

  it('extractPronunciations returns BrE and AmE IPA', () => {
    const $ = load(html);
    const [bre, ame] = extractPronunciations($);
    expect(bre).toBe('/ˈpɒz.ɪt/');
    expect(ame).toBe('/ˈpɑː.zɪt/');
  });

  it('extractEntries returns two POS blocks', () => {
    const $ = load(html);
    const entries = extractEntries($);
    expect(entries).toHaveLength(2);
    expect(entries[0].pos).toBe('verb');
    expect(entries[1].pos).toBe('noun');
  });

  it('verb entry has correct definition and CEFR', () => {
    const $ = load(html);
    const entries = extractEntries($);
    const verbSense = entries[0].senses[0];
    expect(verbSense.definition).toBe('to suggest that something is true');
    expect(verbSense.cefrLevel).toBe('C2');
    expect(verbSense.grammar).toBe('[T]');
  });

  it('verb entry has examples', () => {
    const $ = load(html);
    const entries = extractEntries($);
    const examples = entries[0].senses[0].examples;
    expect(examples).toContain('Scientists posit that the universe began with a big bang.');
    expect(examples).toContain('She posited a connection between the two events.');
  });

  it('extractCorpusExamples returns corpus sentences', () => {
    const $ = load(html);
    const corpus = extractCorpusExamples($);
    expect(corpus).toHaveLength(1);
    expect(corpus[0]).toBe('These findings posit a new direction for research in this field.');
  });

  it('extractWordFamily returns all word family entries', () => {
    const $ = load(html);
    const family = extractWordFamily($);
    expect(family).toHaveLength(3);
    const words = family.map((e) => e.word);
    expect(words).toContain('posit');
    expect(words).toContain('position');
    expect(words).toContain('positive');
  });

  it('word family entries have correct POS', () => {
    const $ = load(html);
    const family = extractWordFamily($);
    const positEntry = family.find((e) => e.word === 'posit');
    expect(positEntry?.partsOfSpeech).toEqual(['verb', 'noun']);
  });

  it('returns null when no entries found', () => {
    const emptyHtml = '<html><body><div class="entry-body"></div></body></html>';
    const result = parseContent(emptyHtml, 'unknown');
    expect(result).toBeNull();
  });
});

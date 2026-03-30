import { describe, it, expect } from 'vitest';
import { renderMasteryCallout, upsertCallout } from '../src/callout-renderer.js';
import type { WordEntry } from '../src/types.js';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const FIXTURES = join(import.meta.dirname, 'fixtures');

function makeEntry(overrides: Partial<WordEntry> = {}): WordEntry {
  return {
    word: 'posit',
    box: 3,
    status: 'reviewing',
    score: 78,
    last_practiced: '2026-03-29',
    next_review: '2026-04-05',
    sessions: 4,
    failures: [],
    best_sentences: [],
    ...overrides,
  };
}

describe('renderMasteryCallout', () => {
  it('renders basic callout', () => {
    const callout = renderMasteryCallout(makeEntry());
    expect(callout).toContain('> [!mastery]');
    expect(callout).toContain('**Status:** reviewing');
    expect(callout).toContain('**Box:** 3');
    expect(callout).toContain('Next review: 2026-04-05');
    expect(callout).toContain('**Score:** 78');
    expect(callout).toContain('Sessions: 4');
  });

  it('omits Failures line when failures is empty', () => {
    const callout = renderMasteryCallout(makeEntry({ failures: [] }));
    expect(callout).not.toContain('**Failures:**');
  });

  it('renders Failures as JSON array', () => {
    const callout = renderMasteryCallout(makeEntry({ failures: ["confused with 'postulate'"] }));
    expect(callout).toContain('**Failures:** ["confused with \'postulate\'"]');
  });
});

describe('upsertCallout', () => {
  it('inserts callout into page with no existing callout', () => {
    const content = readFileSync(join(FIXTURES, 'posit-no-mastery.md'), 'utf8');
    const entry = makeEntry();
    const updated = upsertCallout(content, entry);
    expect(updated).toContain('> [!mastery]');
    expect(updated).toContain('> [!info] posit');
  });

  it('replaces existing callout in page with mastery data', () => {
    const content = readFileSync(join(FIXTURES, 'posit-full-mastery.md'), 'utf8');
    const entry = makeEntry({ box: 4, status: 'mastered', score: 92, next_review: '2026-04-12' });
    const updated = upsertCallout(content, entry);
    // New callout present
    expect(updated).toContain('**Status:** mastered');
    expect(updated).toContain('**Box:** 4');
    // Old callout gone
    expect(updated).not.toContain('**Box:** 3  ·  Next review: 2026-04-05');
    // Only one callout
    const matches = updated.match(/> \[!mastery\]/g);
    expect(matches?.length).toBe(1);
  });

  it('History section is preserved after callout replacement', () => {
    const content = readFileSync(join(FIXTURES, 'posit-full-mastery.md'), 'utf8');
    const entry = makeEntry({ box: 4, status: 'mastered', score: 92 });
    const updated = upsertCallout(content, entry);
    expect(updated).toContain('### History');
    expect(updated).toContain('box 2→3');
  });
});

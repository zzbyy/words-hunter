import { describe, it, expect } from 'vitest';
import { advance, isDue, deriveStatus, BOX_INTERVALS, MASTERY_THRESHOLD, addDays } from '../src/srs/scheduler.js';
import type { WordEntry } from '../src/types.js';

const TODAY = '2026-03-29';

describe('advance — SRS scheduler', () => {
  it('box 1 success → box 2', () => {
    const result = advance(1, MASTERY_THRESHOLD, TODAY);
    expect(result.box).toBe(2);
    expect(result.status).toBe('learning');
    expect(result.graduated).toBe(false);
  });

  it('box 1 fail → stays box 1 (floor)', () => {
    const result = advance(1, 50, TODAY);
    expect(result.box).toBe(1);
    expect(result.status).toBe('learning');
  });

  it('box 5 success → stays box 5 (ceiling)', () => {
    const result = advance(5, 95, TODAY);
    expect(result.box).toBe(5);
    expect(result.status).toBe('mastered');
  });

  it('box 3 fail → box 2', () => {
    const result = advance(3, 60, TODAY);
    expect(result.box).toBe(2);
    expect(result.status).toBe('learning');
  });

  it('box 3 success → box 4, graduated', () => {
    const result = advance(3, MASTERY_THRESHOLD, TODAY);
    expect(result.box).toBe(4);
    expect(result.status).toBe('mastered');
    expect(result.graduated).toBe(true);
  });

  it('box 4 success → box 5, not graduated (already mastered)', () => {
    const result = advance(4, 90, TODAY);
    expect(result.box).toBe(5);
    expect(result.status).toBe('mastered');
    expect(result.graduated).toBe(false);
  });

  it('score exactly at mastery_threshold (85) → success', () => {
    const result = advance(2, 85, TODAY);
    expect(result.box).toBe(3);
  });

  it('score 84 → failure', () => {
    const result = advance(2, 84, TODAY);
    expect(result.box).toBe(1);
  });

  it('all 5 box intervals are correct', () => {
    expect(BOX_INTERVALS[1]).toBe(1);
    expect(BOX_INTERVALS[2]).toBe(3);
    expect(BOX_INTERVALS[3]).toBe(7);
    expect(BOX_INTERVALS[4]).toBe(14);
    expect(BOX_INTERVALS[5]).toBe(30);
  });

  it('next_review is today + box interval', () => {
    const result = advance(1, 90, TODAY);  // box 1 → 2, interval 3
    expect(result.next_review).toBe(addDays(TODAY, BOX_INTERVALS[2]));
  });
});

describe('deriveStatus', () => {
  it('box 1 → learning', () => expect(deriveStatus(1)).toBe('learning'));
  it('box 2 → learning', () => expect(deriveStatus(2)).toBe('learning'));
  it('box 3 → reviewing', () => expect(deriveStatus(3)).toBe('reviewing'));
  it('box 4 → mastered', () => expect(deriveStatus(4)).toBe('mastered'));
  it('box 5 → mastered', () => expect(deriveStatus(5)).toBe('mastered'));
});

describe('isDue', () => {
  const makeEntry = (next_review: string): WordEntry => ({
    word: 'posit',
    box: 1,
    status: 'learning',
    score: 0,
    last_practiced: '',
    next_review,
    sessions: 0,
    failures: [],
    best_sentences: [],
  });

  it('due today → true', () => expect(isDue(makeEntry(TODAY), TODAY)).toBe(true));
  it('due yesterday → true', () => expect(isDue(makeEntry('2026-03-28'), TODAY)).toBe(true));
  it('due tomorrow → false', () => expect(isDue(makeEntry('2026-03-30'), TODAY)).toBe(false));
});

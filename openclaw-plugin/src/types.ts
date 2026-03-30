// ============================================================
// ToolResult<T> — discriminated union for all tool returns
// ============================================================

export type ToolResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: ToolError };

export type ToolError =
  | { code: 'VAULT_NOT_FOUND';  message: string }
  | { code: 'FILE_NOT_FOUND';   message: string; word: string }
  | { code: 'PARSE_ERROR';      message: string; word?: string }
  | { code: 'WRITE_FAILED';     message: string }
  | { code: 'ALREADY_EDITED';   message: string; word: string }
  | { code: 'VAULT_ESCAPE';     message: string; path: string }
  | { code: 'NaN_SCORE';        message: string; field: string }
  | { code: 'INVALID_INPUT';   message: string; field: string }
  | { code: 'FILE_EXISTS';     message: string };

export function ok<T>(data: T): ToolResult<T> {
  return { ok: true, data };
}

export function err(error: ToolError): ToolResult<never> {
  return { ok: false, error };
}

// ============================================================
// Config bridge schema (.wordshunter/config.json)
// ============================================================

export interface VaultConfig {
  vault_path: string;
  words_folder: string;  // subfolder name, or "" for vault root
}

// ============================================================
// Mastery JSON sidecar schema (.wordshunter/mastery.json)
// ============================================================

export interface BestSentence {
  text: string;
  date: string;   // YYYY-MM-DD
  score: number;  // 0–100
}

export interface WordEntry {
  word: string;
  box: 1 | 2 | 3 | 4 | 5;
  status: 'learning' | 'reviewing' | 'mastered';
  score: number;             // latest composite score 0–100
  last_practiced: string;    // YYYY-MM-DD
  next_review: string;       // YYYY-MM-DD
  sessions: number;
  failures: string[];
  best_sentences: BestSentence[];
}

export interface MasteryStore {
  version: 1;
  words: Record<string, WordEntry>;
}

// ============================================================
// Pending nudges queue (.wordshunter/pending-nudges.json)
// ============================================================

export interface PendingNudge {
  word: string;
  nudge_due_at: string;   // ISO8601
  created_at: string;     // ISO8601
}

export interface NudgeQueue {
  version: 1;
  nudges: PendingNudge[];
}

// ============================================================
// Scoring rubric
// ============================================================

export interface SessionScore {
  meaning: number;      // 0–15
  register: number;     // 0–10
  collocation: number;  // 0–10
  grammar: number;      // 0–5
  total: number;        // sum, 0–40 scaled to 0–100
}

// ============================================================
// vault_summary output
// ============================================================

export interface VaultSummary {
  total: number;
  mastered: number;
  reviewing: number;
  learning: number;
  due_today: number;
  last_session: string | null;  // YYYY-MM-DD or null if never
}

// ============================================================
// Scan vault output
// ============================================================

export type ScanFilter = 'all' | 'due' | 'new';

export interface ScannedWord {
  word: string;
  status: WordEntry['status'] | 'new';
  next_review: string | null;
}

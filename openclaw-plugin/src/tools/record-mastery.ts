import fs from 'node:fs/promises';
import path from 'node:path';
import { ToolResult, VaultConfig, WordEntry, BestSentence, ok, err } from '../types.js';
import { masteryJsonPath, wordsFolderPath, assertInVault, readMasteryStore, writeMasteryStore, validateWord } from '../vault.js';
import { advance, todayString, MASTERY_THRESHOLD } from '../srs/scheduler.js';
import { upsertCallout } from '../callout-renderer.js';

export interface RecordMasteryInput {
  word: string;
  score: number;            // 0–100 composite score
  best_sentence?: string;   // optional sentence to save if score >= mastery threshold
  failure_note?: string;    // optional confusion note to append
}

export interface RecordMasteryResult {
  word: string;
  box: WordEntry['box'];
  status: WordEntry['status'];
  next_review: string;
  graduated: boolean;
}

/**
 * record_mastery — record a practice session result.
 *
 * 1. Validates score (NaN_SCORE if invalid).
 * 2. Reads mastery.json.
 * 3. Advances SRS schedule.
 * 4. Appends to ### History in the .md page.
 * 5. Writes mastery.json atomically.
 * 6. Regenerates > [!mastery] callout in .md page.
 * 7. Returns new schedule + graduated flag.
 */
export async function recordMastery(
  config: VaultConfig,
  input: RecordMasteryInput,
): Promise<ToolResult<RecordMasteryResult>> {
  // Validate inputs
  const wordErr = validateWord(input.word);
  if (wordErr) return { ok: false, error: wordErr };

  if (typeof input.score !== 'number' || !isFinite(input.score)) {
    return err({ code: 'NaN_SCORE', message: `Invalid score: ${input.score}`, field: 'score' });
  }
  const score = Math.max(0, Math.min(100, input.score));

  const wordLower = input.word.toLowerCase();
  const jsonPath = masteryJsonPath(config);
  const today = todayString();

  // Read current store
  const storeResult = await readMasteryStore(jsonPath);
  if (!storeResult.ok) return storeResult;
  const store = storeResult.data;

  // Get or initialise entry
  const existing = store.words[wordLower];
  const currentBox: 1 | 2 | 3 | 4 | 5 = existing?.box ?? 1;

  // Advance schedule
  const { box, status, next_review, graduated } = advance(currentBox, score, today);

  // Build updated best_sentences
  const bestSentences: BestSentence[] = existing?.best_sentences ?? [];
  if (input.best_sentence && score >= MASTERY_THRESHOLD) {
    bestSentences.push({ text: input.best_sentence, date: today, score });
  }

  // Build updated failures
  const failures: string[] = existing?.failures ?? [];
  if (input.failure_note && score < MASTERY_THRESHOLD) {
    failures.push(input.failure_note);
  }

  const updatedEntry: WordEntry = {
    word: wordLower,
    box,
    status,
    score,
    last_practiced: today,
    next_review,
    sessions: (existing?.sessions ?? 0) + 1,
    failures,
    best_sentences: bestSentences,
  };
  store.words[wordLower] = updatedEntry;

  // Write mastery.json atomically
  const writeResult = await writeMasteryStore(jsonPath, store);
  if (!writeResult.ok) return writeResult;

  // Update .md page: append History + regenerate callout
  const wordsDir = wordsFolderPath(config);
  const mdPath = path.join(wordsDir, `${wordLower}.md`);
  const escapeErr = assertInVault(config.vault_path, mdPath);
  if (escapeErr) return { ok: false, error: escapeErr };

  try {
    let content = await fs.readFile(mdPath, 'utf8');

    // Append history line (sentences = 1 if a sentence was saved this session, 0 otherwise)
    const sentencesThisSession = (input.best_sentence && score >= MASTERY_THRESHOLD) ? 1 : 0;
    const historyLine = `- ${today}: box ${currentBox}→${box}, score ${score}, sentences: ${sentencesThisSession}`;
    const historyRegex = /^### History\n/m;
    if (historyRegex.test(content)) {
      content = content.replace(historyRegex, `### History\n${historyLine}\n`);
    } else {
      // Insert ### History section inside ## Mastery callout area, or append
      const masteryCalloutRegex = /^> \[!mastery\]/m;
      if (masteryCalloutRegex.test(content)) {
        // Append after the callout block
        content = content.replace(
          /(> \[!mastery\][\s\S]*?)(\n\n|\n##|\n---)/m,
          `$1\n\n### History\n${historyLine}\n$2`,
        );
      } else {
        content += `\n\n### History\n${historyLine}\n`;
      }
    }

    // Regenerate callout
    content = upsertCallout(content, updatedEntry);

    // Write .md atomically
    const tmp = path.join(
      path.dirname(mdPath),
      `.wh-mastery-${wordLower}-${Date.now()}-${Math.random().toString(36).slice(2)}.tmp`,
    );
    await fs.writeFile(tmp, content, 'utf8');
    await fs.rename(tmp, mdPath);
  } catch {
    // .md write failure is non-fatal — mastery.json is already saved
    // The callout is a display view; a failed update won't corrupt state.
    // words-hunter repair can regenerate it.
  }

  return ok({ word: wordLower, box, status, next_review, graduated });
}

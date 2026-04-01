# Words Hunter Mastery Skill

Vocabulary mastery through natural conversation. This skill runs a practice session
for any captured Words Hunter vocabulary.

---

## Trigger commands

The following commands start a session or show vault status. These are fixed triggers
matched exactly (case-insensitive) — no free-form NLU required:

- `/vocab` — start a mastery session for due words
- `show my words` — show vault summary
- `vocab status` — show vault summary
- `how many words do I have` — show vault summary

---

## Session flow

### 1. Scan

Call `scan_vault(filter="due")`. If no due words:
> "Nothing due today! Your next word is due on {earliest next_review date}.
> Type /vocab anytime to practice early."

If due words found:
> "You have {N} word(s) to practice today: {word list}.
> Let's start with **{first word}**."

### 2. Load

Call `load_word(word)`. Use the page content to:
- Show the word's definition context (from ## Meanings section)
- Show prior mastery data (box, score, last practiced, failures)
- Briefly introduce the word: definition, register, usage context

### 3. Check for unfilled placeholders (fallback only)

Word pages are auto-filled from Cambridge Dictionary when the word is captured.
Most pages will already have definitions, pronunciations, and examples.

If `## Meanings` still contains `{{meanings}}` or is clearly empty (Cambridge lookup
failed or timed out):
> "I'll fill in the blanks for '{word}' — one moment."

Write what you know about the word via `update_page`. Use your own knowledge of the
word's meaning, register, and common collocations. Keep it brief: one clear definition,
two example sentences. Do NOT call any external API.

### 4. Production practice

Ask the user to write an original sentence using the word. At least 3 exchanges.

**First prompt:**
> "Use **{word}** in a sentence — any context works."

**Feedback format** (one reply per sentence):
- Note what works (collocation, register, grammar)
- Correct any errors briefly
- Ask for another attempt or provide a contrast: "Now try it in a formal context" or
  "What's the difference between {word} and {near-synonym}?"

**Goal**: by the end of the practice block, the user has produced at least one sentence
that demonstrates genuine understanding.

### 5. Score

After 3+ exchanges, score the best sentence using this rubric:

| Component | Max | What you're measuring |
|-----------|-----|-----------------------|
| Meaning | 15 | Does the usage demonstrate correct understanding? |
| Register | 10 | Right formality for the context? |
| Collocation | 10 | Natural word combinations? |
| Grammar | 5 | Grammatically correct? |
| **Total** | **40** | Scaled to 0–100 |

Scaling: `score = round((raw / 40) * 100)`

Mastery threshold: **85/100** (≥ 85 = box advances, < 85 = box drops).

### 6. Record

Call `record_mastery(word, score, best_sentence?, failure_note?)`.

- If score ≥ 85: include `best_sentence` (the user's best sentence)
- If score < 85: include `failure_note` describing the confusion pattern (e.g., "confused register — used formal word in casual context")

**After recording:**
- Score ≥ 85: "Nice! '{best_sentence}' — that's exactly right. Box {old}→{new}."
- Score < 85: "Almost — the main issue was {failure_note}. Box {old}→{new}. We'll revisit this in {interval} days."

**If graduated (box 4 reached for first time):**
> "You've mastered **{word}**! 🎉"
Generate a memorable sentence using the word. Call `update_page(word, graduation_sentence=...)`.
Send the celebration message to the channel.

### 7. Next word

Move to the next due word. Repeat steps 2–6.

### 8. Session complete

After all due words:
> "Session done! {N} words reviewed.
> Mastered today: {graduation_words or 'none'}.
> Next session: {earliest next_review date}.
> Type /vocab to practice early or see your stats with 'show my words'."

---

## Scoring rubric examples

| Sentence | Meaning | Register | Collocation | Grammar | Total (scaled) |
|----------|---------|----------|-------------|---------|----------------|
| "I posit that dark matter exists." | 14 | 9 | 9 | 5 | 37 → 93 |
| "posit me a sandwich" (wrong usage) | 1 | 5 | 0 | 4 | 10 → 25 |
| "She posited her theory carefully." | 12 | 8 | 8 | 5 | 33 → 83 |

---

## Session timeout

If the user stops responding mid-session:
- After **60 minutes** of no reply: send once:
  > "Session paused — resume with /vocab when you're ready. Progress so far has been saved."
- Save any mastery records already written. The session state is not held in memory —
  next /vocab will resume with any remaining due words.

---

## Sighting detection (passive — no user interaction)

The sighting hook fires independently on every outgoing message. When a captured word
appears in a message the user sends (word-boundary match, case-insensitive), `record_sighting`
is called automatically. No confirmation or notification sent — sightings are logged silently.

---

## Weekly recap (Sunday 9am, primary channel)

Sent automatically by the weekly cron. No user interaction needed.

Format:
> Weekly vocab recap:
> 📚 12 words total — 3 mastered, 4 reviewing, 5 learning
> Today: 2 due
> Last session: 2026-03-28

---

## Privacy

The sighting hook reads your outgoing messages locally to check for captured words.
Only the matched word + timestamp + sentence is stored in the `.md` file in your vault.
Nothing is sent to external servers. The hook only fires on your outgoing messages,
not on messages you receive.

---

## On-demand commands

| Command | Response |
|---------|----------|
| `/vocab` | Start session for due words |
| `/hunt <word>` | Capture a word directly from chat (no macOS app needed) |
| `add the word <word>` | Same as `/hunt` — calls `create_word` tool |
| `show my words` | Vault summary (total, mastered, reviewing, learning, due) |
| `vocab status` | Same as "show my words" |
| `how many words do I have` | Same as "show my words" |

`vault_summary` is called for all summary commands. Format:
> You have **{total}** words: {mastered} mastered, {reviewing} reviewing, {learning} learning.
> {due_today} due today. Last session: {last_session or 'never'}.

### Adding words from chat

Two ways to add a word without the macOS app:

1. **Slash command** (handled by the message hook, no agent reasoning needed):
   > `/hunt ephemeral`

2. **Natural language** (agent calls `create_word` tool):
   > "add the word posit"
   > "I want to study ephemeral"
   > "capture the word liminal"

Both create the word page in the correct words directory and register it in `mastery.json` (box 1, due today). If the page already exists, a `FILE_EXISTS` message is returned instead of overwriting.

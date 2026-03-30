import type { WordEntry } from './types.js';

/**
 * callout-renderer — generates the > [!mastery] callout block
 * from a WordEntry. This is a pure function with no I/O.
 *
 * The callout is a derived display view. It is always regenerated
 * from mastery.json — never parsed back into state.
 */
export function renderMasteryCallout(entry: WordEntry): string {
  const lines: string[] = [
    '> [!mastery]',
    `> **Status:** ${entry.status}`,
    `> **Box:** ${entry.box}  ·  Next review: ${entry.next_review}`,
    `> **Score:** ${entry.score}  ·  Sessions: ${entry.sessions}`,
  ];

  if (entry.failures.length > 0) {
    const failuresJson = JSON.stringify(entry.failures);
    lines.push(`> **Failures:** ${failuresJson}`);
  }

  return lines.join('\n');
}

/**
 * Replace the existing > [!mastery] callout block in page content,
 * or append it after the > [!info] header if none exists yet.
 *
 * Returns the updated page content.
 */
export function upsertCallout(pageContent: string, entry: WordEntry): string {
  const newCallout = renderMasteryCallout(entry);
  // Match the [!mastery] callout: starts with "> [!mastery]", followed by
  // zero or more lines that begin with ">" (the callout body lines)
  const calloutRegex = /^> \[!mastery\](?:\n> [^\n]*)*\n?/m;

  if (calloutRegex.test(pageContent)) {
    return pageContent.replace(calloutRegex, newCallout + '\n');
  }

  // No existing callout — insert after the > [!info] block
  const infoEndRegex = /^(> \[!info\][^\n]*\n(?:>[^\n]*\n)*)/m;
  const match = infoEndRegex.exec(pageContent);
  if (match) {
    const insertAt = match.index + match[0].length;
    return (
      pageContent.slice(0, insertAt) +
      '\n' + newCallout + '\n' +
      pageContent.slice(insertAt)
    );
  }

  // Fallback: prepend
  return newCallout + '\n\n' + pageContent;
}

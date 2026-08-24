export interface CardSplit {
  front: string;
  back: string;
}

export interface ParagraphRange {
  text: string;
  start: number;
  end: number;
}

function finishCard(rawFront: string, rawBack: string): CardSplit | null {
  const front = rawFront.trim();
  const back = rawBack.trim();
  if (front.length === 0 || back.length === 0) return null;
  return { front, back };
}

/**
 * Splits a paragraph into flashcard sides. Mirrors the Swift rules: try the
 * first newline, then " — ", then ": " — first match wins; both trimmed sides
 * must be non-empty or the split is rejected (returns null).
 */
export function splitParagraphToCard(paragraph: string): CardSplit | null {
  const newlineIndex = paragraph.indexOf("\n");
  if (newlineIndex !== -1) {
    return finishCard(paragraph.slice(0, newlineIndex), paragraph.slice(newlineIndex + 1));
  }
  for (const separator of [" — ", ": "]) {
    const index = paragraph.indexOf(separator);
    if (index !== -1) {
      return finishCard(paragraph.slice(0, index), paragraph.slice(index + separator.length));
    }
  }
  return null;
}

/** Returns the paragraph containing `caretIndex`, or null when it is blank. */
export function selectParagraphAround(text: string, caretIndex: number): ParagraphRange | null {
  const caret = Math.min(Math.max(caretIndex, 0), text.length);
  const start = text.lastIndexOf("\n", caret - 1) + 1;
  const newlineAfter = text.indexOf("\n", caret);
  const end = newlineAfter === -1 ? text.length : newlineAfter;
  const paragraph = text.slice(start, end);
  if (paragraph.trim().length === 0) return null;
  return { text: paragraph, start, end };
}

/** Trimmed, whitespace-collapsed title, or null when empty. */
export function extractTaskTitle(paragraph: string): string | null {
  const title = paragraph.replace(/\s+/gu, " ").trim();
  return title.length === 0 ? null : title;
}

/** Trimmed body, or null when empty. */
export function extractQuestionText(paragraph: string): string | null {
  const body = paragraph.trim();
  return body.length === 0 ? null : body;
}

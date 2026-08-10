import {Text} from "@codemirror/state";

export function normalizedDocumentText(text: string) {
  return text.replace(/\r\n/g, "\n");
}

export function replacementChange(currentText: string, requestedText: string) {
  const targetText = normalizedDocumentText(requestedText);
  let prefix = 0;
  const sharedLength = Math.min(currentText.length, targetText.length);
  while (prefix < sharedLength && currentText.charCodeAt(prefix) === targetText.charCodeAt(prefix)) prefix += 1;
  let currentSuffix = currentText.length;
  let targetSuffix = targetText.length;
  while (currentSuffix > prefix && targetSuffix > prefix
      && currentText.charCodeAt(currentSuffix - 1) === targetText.charCodeAt(targetSuffix - 1)) {
    currentSuffix -= 1;
    targetSuffix -= 1;
  }
  return {from: prefix, to: currentSuffix, insert: targetText.slice(prefix, targetSuffix)};
}

export interface NormalizedSourceChange {
  from: number;
  to: number;
  insert: string;
  removed?: string;
}

function rope(source: string) {
  return Text.of(source.split("\n"));
}

function crlfCount(source: string) {
  let count = 0;
  for (let index = source.indexOf("\r\n"); index >= 0;
    index = source.indexOf("\r\n", index + 2)) count += 1;
  return count;
}

function exactOffset(
  exact: Text,
  normalized: Text,
  requestedOffset: number,
) {
  if (!Number.isSafeInteger(requestedOffset)
      || requestedOffset < 0
      || requestedOffset > normalized.length) return null;
  const normalizedLine = normalized.lineAt(requestedOffset);
  const exactLine = exact.line(normalizedLine.number);
  const column = requestedOffset - normalizedLine.from;
  return exactLine.from + column;
}

/**
 * Maps one CodeMirror UTF-16 offset back into the exact source mirror.
 * CodeMirror represents every CRLF as one LF; the exact mirror retains both
 * code units so untouched line endings can survive a full-buffer query.
 */
export function exactOffsetForNormalizedOffset(exactSource: string, requestedOffset: number) {
  return exactOffset(
    rope(exactSource),
    rope(normalizedDocumentText(exactSource)),
    requestedOffset,
  );
}

/**
 * Owns the exact line-ending mirror for one CodeMirror document.
 *
 * The text remains the sole exact-source value. The CRLF array is derived
 * positional metadata that maps CodeMirror's normalized offsets in O(log n)
 * and is updated by the same transaction, rather than rescanning the complete
 * note for every insertion point and deletion boundary.
 */
export class ExactSourceMirror {
  private exact: Text;
  private normalized: Text;
  private crlfLineBreakCount: number;

  constructor(source = "") {
    this.exact = rope(source);
    this.normalized = rope(normalizedDocumentText(source));
    this.crlfLineBreakCount = crlfCount(source);
  }

  /**
   * Materializing the complete String is intentionally an explicit snapshot
   * boundary. Ordinary input only edits the persistent Text ropes below.
   */
  get text() { return this.exact.toString(); }

  replace(source: string) {
    this.exact = rope(source);
    this.normalized = rope(normalizedDocumentText(source));
    this.crlfLineBreakCount = crlfCount(source);
  }

  apply(changes: readonly NormalizedSourceChange[]) {
    if (changes.length === 0) return true;
    const ordered = [...changes]
      .map((change) => ({...change, insert: normalizedDocumentText(change.insert)}))
      .sort((left, right) => left.from - right.from || left.to - right.to);
    let previousTo = -1;
    for (const change of ordered) {
      if (change.from < previousTo || change.to < change.from) return false;
      previousTo = change.to;
    }

    const usesCRLF = this.crlfLineBreakCount > 0;
    const exactChanges = ordered.map((change) => {
      const from = exactOffset(this.exact, this.normalized, change.from);
      const to = exactOffset(this.exact, this.normalized, change.to);
      if (from === null || to === null || to < from) return null;
      if (change.removed !== undefined
          && this.normalized.sliceString(change.from, change.to) !== change.removed) return null;
      const exactInsert = usesCRLF ? change.insert.replaceAll("\n", "\r\n") : change.insert;
      return {
        ...change,
        exactFrom: from,
        exactTo: to,
        exactInsert,
        removedCRLFCount: crlfCount(this.exact.sliceString(from, to)),
        insertedCRLFCount: crlfCount(exactInsert),
      };
    });
    if (exactChanges.some((change) => change === null)) return false;

    for (const change of exactChanges
      .filter((candidate): candidate is NonNullable<typeof candidate> => candidate !== null)
      .sort((left, right) => right.from - left.from)) {
      this.exact = this.exact.replace(
        change.exactFrom,
        change.exactTo,
        rope(change.exactInsert),
      );
      this.normalized = this.normalized.replace(
        change.from,
        change.to,
        rope(change.insert),
      );
      this.crlfLineBreakCount += change.insertedCRLFCount - change.removedCRLFCount;
    }
    return true;
  }
}

/**
 * Applies CodeMirror changes to the exact source mirror without rebuilding
 * untouched text from CodeMirror's one-line-separator representation.
 */
export function applyNormalizedChangesToExactSource(
  exactSource: string,
  changes: readonly NormalizedSourceChange[],
) {
  const mirror = new ExactSourceMirror(exactSource);
  return mirror.apply(changes) ? mirror.text : null;
}

function isFrontmatterOpening(text: string) {
  return /^---[ \t]*$/.test(text.replace(/^\uFEFF/, ""));
}

export function frontmatterBoundary(doc: Text) {
  if (!isFrontmatterOpening(doc.line(1).text)) {
    return {endLine: 0, unclosed: false};
  }
  if (doc.lines < 2) return {endLine: 0, unclosed: true};
  for (let number = 2; number <= doc.lines; number += 1) {
    if (/^---[ \t]*$/.test(doc.line(number).text)) {
      return {endLine: number, unclosed: false};
    }
  }
  return {endLine: 0, unclosed: true};
}

export function frontmatterEndLine(doc: Text) {
  return frontmatterBoundary(doc).endLine;
}

/** Returns the first body offset in CodeMirror's normalized UTF-16 space. */
export function frontmatterBodyOffset(doc: Text) {
  const endLine = frontmatterEndLine(doc);
  if (endLine === 0) return 0;
  return endLine < doc.lines ? doc.line(endLine + 1).from : doc.line(endLine).to;
}

export function hasUnclosedFrontmatter(doc: Text) {
  return frontmatterBoundary(doc).unclosed;
}

import type {Text} from "@codemirror/state";

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

function lowerBound(values: readonly number[], target: number) {
  let low = 0;
  let high = values.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (values[middle] < target) low = middle + 1;
    else high = middle;
  }
  return low;
}

function crlfNormalizedOffsets(source: string) {
  const offsets: number[] = [];
  let exactOffset = 0;
  let normalizedOffset = 0;
  while (exactOffset < source.length) {
    if (source.charCodeAt(exactOffset) === 13
        && source.charCodeAt(exactOffset + 1) === 10) {
      offsets.push(normalizedOffset);
      exactOffset += 2;
    } else {
      exactOffset += 1;
    }
    normalizedOffset += 1;
  }
  return offsets;
}

function exactOffsetFromCRLFIndex(
  exactLength: number,
  crlfOffsets: readonly number[],
  requestedOffset: number,
) {
  const normalizedLength = exactLength - crlfOffsets.length;
  if (!Number.isSafeInteger(requestedOffset)
      || requestedOffset < 0
      || requestedOffset > normalizedLength) return null;
  return requestedOffset + lowerBound(crlfOffsets, requestedOffset);
}

/**
 * Maps one CodeMirror UTF-16 offset back into the exact source mirror.
 * CodeMirror represents every CRLF as one LF; the exact mirror retains both
 * code units so untouched line endings can survive a full-buffer query.
 */
export function exactOffsetForNormalizedOffset(exactSource: string, requestedOffset: number) {
  return exactOffsetFromCRLFIndex(
    exactSource.length,
    crlfNormalizedOffsets(exactSource),
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
  private value: string;
  private crlfOffsets: number[];

  constructor(source = "") {
    this.value = source;
    this.crlfOffsets = crlfNormalizedOffsets(source);
  }

  get text() { return this.value; }

  replace(source: string) {
    this.value = source;
    this.crlfOffsets = crlfNormalizedOffsets(source);
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

    const usesCRLF = this.crlfOffsets.length > 0;
    const exactChanges = ordered.map((change) => {
      const from = exactOffsetFromCRLFIndex(
        this.value.length,
        this.crlfOffsets,
        change.from,
      );
      const to = exactOffsetFromCRLFIndex(
        this.value.length,
        this.crlfOffsets,
        change.to,
      );
      if (from === null || to === null || to < from) return null;
      if (change.removed !== undefined
          && normalizedDocumentText(this.value.slice(from, to)) !== change.removed) return null;
      return {
        ...change,
        exactFrom: from,
        exactTo: to,
        exactInsert: usesCRLF ? change.insert.replaceAll("\n", "\r\n") : change.insert,
      };
    });
    if (exactChanges.some((change) => change === null)) return false;

    for (const change of exactChanges
      .filter((candidate): candidate is NonNullable<typeof candidate> => candidate !== null)
      .sort((left, right) => right.from - left.from)) {
      this.value = this.value.slice(0, change.exactFrom)
        + change.exactInsert
        + this.value.slice(change.exactTo);
    }

    let nextCRLFOffsets = this.crlfOffsets;
    for (const change of [...ordered].sort((left, right) => right.from - left.from)) {
      const firstRemoved = lowerBound(nextCRLFOffsets, change.from);
      const afterRemoved = lowerBound(nextCRLFOffsets, change.to);
      const delta = change.insert.length - (change.to - change.from);
      const insertedOffsets: number[] = [];
      if (usesCRLF) {
        for (let index = change.insert.indexOf("\n"); index >= 0;
          index = change.insert.indexOf("\n", index + 1)) {
          insertedOffsets.push(change.from + index);
        }
      }
      nextCRLFOffsets = [
        ...nextCRLFOffsets.slice(0, firstRemoved),
        ...insertedOffsets,
        ...nextCRLFOffsets.slice(afterRemoved).map((offset) => offset + delta),
      ];
    }
    this.crlfOffsets = nextCRLFOffsets;
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
  return text.replace(/^\uFEFF/, "").trim() === "---";
}

export function frontmatterBoundary(doc: Text) {
  if (doc.lines < 2 || !isFrontmatterOpening(doc.line(1).text)) {
    return {endLine: 0, unclosed: false};
  }
  for (let number = 2; number <= doc.lines; number += 1) {
    if (doc.line(number).text.trim() === "---") return {endLine: number, unclosed: false};
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

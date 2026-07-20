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
}

/**
 * Maps one CodeMirror UTF-16 offset back into the exact source mirror.
 * CodeMirror represents every CRLF as one LF; the exact mirror retains both
 * code units so untouched line endings can survive a full-buffer query.
 */
export function exactOffsetForNormalizedOffset(exactSource: string, requestedOffset: number) {
  if (!Number.isSafeInteger(requestedOffset) || requestedOffset < 0) return null;
  let exactOffset = 0;
  let normalizedOffset = 0;
  while (exactOffset < exactSource.length && normalizedOffset < requestedOffset) {
    if (exactSource.charCodeAt(exactOffset) === 13
        && exactSource.charCodeAt(exactOffset + 1) === 10) {
      exactOffset += 2;
    } else {
      exactOffset += 1;
    }
    normalizedOffset += 1;
  }
  return normalizedOffset === requestedOffset ? exactOffset : null;
}

/**
 * Applies CodeMirror changes to the exact source mirror without rebuilding
 * untouched text from CodeMirror's one-line-separator representation.
 */
export function applyNormalizedChangesToExactSource(
  exactSource: string,
  changes: readonly NormalizedSourceChange[],
) {
  const usesCRLF = exactSource.includes("\r\n");
  const exactChanges = changes.map((change) => {
    const from = exactOffsetForNormalizedOffset(exactSource, change.from);
    const to = exactOffsetForNormalizedOffset(exactSource, change.to);
    if (from === null || to === null || to < from) return null;
    return {
      from,
      to,
      insert: usesCRLF ? change.insert.replaceAll("\n", "\r\n") : change.insert,
    };
  });
  if (exactChanges.some((change) => change === null)) return null;

  let result = exactSource;
  for (const change of exactChanges
    .filter((candidate): candidate is {from: number; to: number; insert: string} => candidate !== null)
    .sort((lhs, rhs) => rhs.from - lhs.from)) {
    result = result.slice(0, change.from) + change.insert + result.slice(change.to);
  }
  return result;
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

export function hasUnclosedFrontmatter(doc: Text) {
  return frontmatterBoundary(doc).unclosed;
}

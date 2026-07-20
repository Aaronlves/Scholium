import type {Transaction} from "@codemirror/state";
import {syntaxTree} from "@codemirror/language";

export interface ProjectionSourceRange {
  from: number;
  to: number;
}

/**
 * CodeMirror may publish a more complete background parse without changing
 * the document or selection. Live projections must rebuild for that
 * transaction or their initial, partial-tree decorations can remain stale
 * until the researcher next moves the selection.
 */
export function transactionChangedSyntaxTree(transaction: Transaction) {
  return syntaxTree(transaction.startState) !== syntaxTree(transaction.state);
}

/**
 * Conservative fast-path guard for a projection whose current index is known
 * to contain no constructs. Deletions can join latent marker fragments and a
 * large insertion must not be truncated, so both require a full rebuild.
 */
export function transactionMayCreateProjection(transaction: Transaction, marker: RegExp) {
  let mayCreate = false;
  transaction.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
    if (mayCreate) return;
    if (toA > fromA || inserted.length > 8_192) {
      mayCreate = true;
      return;
    }
    mayCreate = marker.test(inserted.toString());
  });
  return mayCreate;
}

/**
 * Allows an existing construct index to move through a bounded plain-text
 * insertion without reparsing the whole document. Deletions, line breaks,
 * syntax markers, and edits at or inside an indexed construct rebuild. Those
 * operations can change Markdown block structure or global footnote meaning.
 */
export function transactionCanMapProjection(
  transaction: Transaction,
  marker: RegExp,
  ranges: readonly ProjectionSourceRange[],
) {
  if (!transaction.docChanged || ranges.length === 0) return false;
  let canMap = true;
  transaction.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
    if (!canMap) return;
    const text = inserted.toString();
    if (toA > fromA || inserted.length > 8_192 || /[\r\n]/.test(text) || marker.test(text)) {
      canMap = false;
      return;
    }
    canMap = !ranges.some((range) => fromA >= range.from && fromA <= range.to);
  });
  return canMap;
}

import type {Text, Transaction} from "@codemirror/state";
import {syntaxTree} from "@codemirror/language";
import {
  boundedProjectionRanges,
  semanticProjectionRanges,
  type SemanticBlockProjection,
  type SemanticInlineProjection,
  type SemanticProjectionRanges,
  type SemanticSourceRange,
} from "./semantic-projection";
import {
  immutableProjectionRanges,
  projectionBoundaryTouches,
  projectionRangesIntersecting,
} from "./projection-index";

export interface ProjectionSourceRange {
  from: number;
  to: number;
}

export interface ProjectionSelectionRange {
  from: number;
  to: number;
  head: number;
  empty: boolean;
}

/**
 * Projection ranges are half-open. A caret at the first source unit activates
 * the construct, while a caret after its closing marker belongs to adjacent
 * source. Non-empty selections activate only on real overlap.
 */
export function selectionIntersectsProjection(
  selection: ProjectionSelectionRange,
  projection: ProjectionSourceRange,
) {
  return selection.empty
    ? selection.head >= projection.from && selection.head < projection.to
    : selection.from < projection.to && selection.to > projection.from;
}

/**
 * A Callout's semantic source excludes its terminal line ending, but its
 * content-end insertion point is still editable Callout content. This is the
 * one block-specific inclusive caret edge; non-empty selections continue to
 * require real half-open overlap.
 */
export function selectionActivatesCallout(
  selection: ProjectionSelectionRange,
  callout: ProjectionSourceRange,
) {
  return selection.empty
    ? selection.head >= callout.from && selection.head <= callout.to
    : selection.from < callout.to && selection.to > callout.from;
}

export function activeProjectionSignature(
  selections: readonly ProjectionSelectionRange[],
  projections: readonly ProjectionSourceRange[],
) {
  const active = new Map<string, ProjectionSourceRange>();
  for (const selection of selections) {
    const from = selection.empty ? selection.head : selection.from;
    const to = selection.empty ? selection.head + 1 : selection.to;
    for (const projection of projectionRangesIntersecting(projections, from, to)) {
      if (!selectionIntersectsProjection(selection, projection)) continue;
      active.set(`${projection.from}:${projection.to}`, projection);
    }
  }
  return [...active.values()]
    .sort((left, right) => left.from - right.from || left.to - right.to)
    .map((projection) => `${projection.from}:${projection.to}`)
    .join("|");
}

/**
 * Captures only selection changes that can alter Live Preview presentation.
 * Moving within one physical line and one already-active inline construct does
 * not require another decoration pass; crossing a line or construct boundary
 * does. Selection direction is intentionally absent because it does not alter
 * the projected Markdown surface.
 */
export function selectionProjectionSignature(
  doc: Text,
  selections: readonly ProjectionSelectionRange[],
  inlineProjections: readonly ProjectionSourceRange[],
  listPrefixProjections: readonly ProjectionSourceRange[] = [],
) {
  const activeLines = selections.map((selection) => {
    const fromLine = doc.lineAt(Math.max(0, Math.min(selection.from, doc.length))).from;
    const toLine = doc.lineAt(Math.max(0, Math.min(selection.to, doc.length))).from;
    return `${fromLine}:${toLine}`;
  }).join("|");
  return [
    activeLines,
    activeProjectionSignature(selections, inlineProjections),
    activeProjectionSignature(selections, listPrefixProjections),
  ].join("#");
}

/**
 * Bounds a selection-only inline refresh to the old and new interaction
 * neighborhoods. This keeps an arrow-key transaction independent of total
 * document length while still refreshing syntax revealed at either caret.
 */
export function selectionAffectedProjectionRanges(
  documentLength: number,
  previousSelections: readonly ProjectionSelectionRange[],
  nextSelections: readonly ProjectionSelectionRange[],
  margin = 2_000,
) {
  return immutableProjectionRanges(boundedProjectionRanges(
    documentLength,
    [...previousSelections, ...nextSelections].map((selection) => ({
      from: selection.from,
      to: selection.to,
    })),
    margin,
  ));
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

function changedContextContainsMarker(
  transaction: Transaction,
  from: number,
  to: number,
  marker: RegExp,
) {
  const doc = transaction.state.doc;
  const boundedFrom = Math.max(0, Math.min(from, doc.length));
  const boundedTo = Math.max(boundedFrom, Math.min(to, doc.length));
  const firstLine = doc.lineAt(boundedFrom);
  const lastLine = doc.lineAt(boundedTo);
  const contextFrom = Math.max(firstLine.from, boundedFrom - 256);
  const contextTo = Math.min(lastLine.to, boundedTo + 256);
  marker.lastIndex = 0;
  return marker.test(doc.sliceString(contextFrom, contextTo));
}

/**
 * Conservative fast-path guard for a projection whose current index is known
 * to contain no constructs. Deletions can join latent marker fragments and a
 * large insertion must not be truncated, so both require a full rebuild.
 */
export function transactionMayCreateProjection(transaction: Transaction, marker: RegExp) {
  let mayCreate = false;
  transaction.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
    if (mayCreate) return;
    if (toA > fromA || inserted.length > 8_192) {
      mayCreate = true;
      return;
    }
    marker.lastIndex = 0;
    mayCreate = marker.test(inserted.toString())
      || changedContextContainsMarker(transaction, fromB, toB, marker);
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
  transaction.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
    if (!canMap) return;
    const text = inserted.toString();
    marker.lastIndex = 0;
    if (toA > fromA || inserted.length > 8_192 || /[\r\n]/.test(text) || marker.test(text)
        || changedContextContainsMarker(transaction, fromB, toB, marker)) {
      canMap = false;
      return;
    }
    canMap = !projectionBoundaryTouches(ranges, fromA);
  });
  return canMap;
}

function rangesOverlap(left: ProjectionSourceRange, right: ProjectionSourceRange) {
  return left.from < right.to && left.to > right.from;
}

function physicalLineNeighborhood(doc: Text, from: number, to: number) {
  const startLine = doc.lineAt(Math.max(0, Math.min(from, doc.length)));
  const endLine = doc.lineAt(Math.max(0, Math.min(to, doc.length)));
  return {
    from: doc.line(Math.max(1, startLine.number - 1)).from,
    to: doc.line(Math.min(doc.lines, endLine.number + 1)).to,
  };
}

function mappedRange(
  range: SemanticSourceRange,
  transaction: Transaction,
): SemanticSourceRange {
  return {
    from: transaction.changes.mapPos(range.from),
    to: transaction.changes.mapPos(range.to),
  };
}

function mappedBlock(
  block: SemanticBlockProjection,
  transaction: Transaction,
): SemanticBlockProjection {
  return {
    ...block,
    ...mappedRange(block, transaction),
    parent: block.parent ? {
      kind: block.parent.kind,
      ...mappedRange(block.parent, transaction),
    } : null,
    markerRanges: block.markerRanges.map((range) => mappedRange(range, transaction)),
    taskMarkerRange: block.taskMarkerRange
      ? mappedRange(block.taskMarkerRange, transaction)
      : null,
  };
}

function mappedInline(
  inline: SemanticInlineProjection,
  transaction: Transaction,
): SemanticInlineProjection {
  return {
    ...inline,
    ...mappedRange(inline, transaction),
    markerRanges: inline.markerRanges.map((range) => mappedRange(range, transaction)),
    visibleRanges: inline.visibleRanges.map((range) => mappedRange(range, transaction)),
    targetRange: inline.targetRange ? mappedRange(inline.targetRange, transaction) : null,
    aliasRange: inline.aliasRange ? mappedRange(inline.aliasRange, transaction) : null,
  };
}

function rangeSignature(range: SemanticSourceRange | null) {
  return range ? `${range.from}:${range.to}` : "-";
}

function projectionTopologySignature(projection: SemanticProjectionRanges) {
  const blocks = projection.blocks.map((block) => [
    "b", block.kind, block.nodeName, block.from, block.to, block.depth,
    block.parent?.kind ?? "-", rangeSignature(block.parent),
    block.headingLevel ?? "-", block.listDepth ?? "-",
    block.markerRanges.map(rangeSignature).join(","),
    rangeSignature(block.taskMarkerRange),
  ].join("|"));
  const inlines = projection.inlines.map((inline) => [
    "i", inline.kind, inline.nodeName, inline.from, inline.to,
    inline.markerRanges.map(rangeSignature).join(","),
    inline.visibleRanges.map(rangeSignature).join(","),
    rangeSignature(inline.targetRange), rangeSignature(inline.aliasRange),
  ].join("|"));
  const literals = projection.literals.map((literal) =>
    ["l", literal.nodeName, literal.from, literal.to].join("|"));
  return [...blocks, ...inlines, ...literals].sort().join("\n");
}

/**
 * Proves that one bounded plain-text insertion preserves the local semantic
 * catalog. This replaces marker-proximity guessing: academic prose may sit
 * beside emphasis, links, or citations without forcing a complete-document
 * projection rebuild, while text that actually completes latent Markdown
 * still changes the catalog and fails closed to a rebuild.
 */
export function transactionCanMapProjectionTopology(
  transaction: Transaction,
  marker: RegExp,
  mutationSensitiveRanges: readonly ProjectionSourceRange[],
  previousSyntax: SemanticProjectionRanges,
) {
  if (!transaction.docChanged) return false;
  const changes: Array<{
    fromA: number;
    toA: number;
    fromB: number;
    toB: number;
    insert: string;
  }> = [];
  transaction.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
    changes.push({fromA, toA, fromB, toB, insert: inserted.toString()});
  });
  if (changes.length !== 1) return false;
  const {fromA, toA, fromB, toB, insert} = changes[0];
  marker.lastIndex = 0;
  if (toA > fromA || insert.length > 8_192 || /[\r\n]/.test(insert) || marker.test(insert)
      || projectionBoundaryTouches(mutationSensitiveRanges, fromA)) {
    return false;
  }

  const oldNeighborhood = physicalLineNeighborhood(transaction.startState.doc, fromA, toA);
  const newNeighborhood = physicalLineNeighborhood(transaction.state.doc, fromB, toB);
  const previousLocal: SemanticProjectionRanges = {
    ...previousSyntax,
    blocks: previousSyntax.blocks
      .filter((block) => rangesOverlap(block, oldNeighborhood))
      .map((block) => mappedBlock(block, transaction)),
    inlines: previousSyntax.inlines
      .filter((inline) => rangesOverlap(inline, oldNeighborhood))
      .map((inline) => mappedInline(inline, transaction)),
    literals: previousSyntax.literals
      .filter((literal) => rangesOverlap(literal, oldNeighborhood))
      .map((literal) => ({...literal, ...mappedRange(literal, transaction)})),
  };
  const nextLocal = semanticProjectionRanges(
    transaction.state,
    [newNeighborhood],
    0,
  );
  return projectionTopologySignature(previousLocal)
    === projectionTopologySignature(nextLocal);
}

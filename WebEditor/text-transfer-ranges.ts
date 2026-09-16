import {EditorSelection, type EditorState} from '@codemirror/state';
import {semanticProjectionRanges, type SemanticBlockProjection, type SemanticSourceRange} from './semantic-projection';
import {frontmatterBoundary} from './state';

function bodyStart(state: EditorState) {
  const boundary = frontmatterBoundary(state.doc);
  if (boundary.unclosed) return state.doc.length;
  return boundary.endLine ? Math.min(state.doc.length, state.doc.line(boundary.endLine).to + 1) : 0;
}

export function lineContentStart(state: EditorState, position: number) {
  const line = state.doc.lineAt(position);
  return line.from === 0 && state.doc.sliceString(0, 1) === '\uFEFF' ? 1 : line.from;
}

/** A complete logical-line range may end before its newline, after it, or at EOF. */
export function isCompleteLineSelection(state: EditorState, range: SemanticSourceRange): boolean {
  if (!Number.isSafeInteger(range.from) || !Number.isSafeInteger(range.to)
      || range.from < 0 || range.to > state.doc.length || range.from >= range.to) return false;
  const end = state.doc.lineAt(range.to);
  return range.from === lineContentStart(state, range.from)
    && (range.to === state.doc.length || range.to === end.to || range.to === end.from);
}

function headingSourceRange(state: EditorState, heading: SemanticBlockProjection): SemanticSourceRange {
  const start = lineContentStart(state, heading.from);
  const end = state.doc.lineAt(heading.to).to;
  return {
    from: /^[ \t]*$/.test(state.doc.sliceString(start, heading.from)) ? start : heading.from,
    to: /^[ \t]*$/.test(state.doc.sliceString(heading.to, end)) ? end : heading.to,
  };
}

function visibleHeadingRange(state: EditorState, heading: SemanticBlockProjection,
  inlines: ReturnType<typeof semanticProjectionRanges>['inlines']): SemanticSourceRange | null {
  const hidden = [...heading.markerRanges];
  for (const inline of inlines) {
    if (inline.from < heading.from || inline.to > heading.to) continue;
    let from = inline.from;
    for (const visible of inline.visibleRanges) {
      if (visible.from > from) hidden.push({from, to: visible.from});
      from = Math.max(from, visible.to);
    }
    if (from < inline.to) hidden.push({from, to: inline.to});
  }
  hidden.sort((a, b) => a.from - b.from || a.to - b.to);
  let cursor = heading.from;
  let first: number | undefined;
  let last = heading.from;
  for (const hiddenRange of [...hidden, {from: heading.to, to: heading.to}]) {
    const end = Math.min(heading.to, hiddenRange.from);
    if (cursor < end) {
      const text = state.doc.sliceString(cursor, end);
      const trimmed = text.trim();
      if (trimmed) {
        first ??= cursor + text.length - text.trimStart().length;
        last = end - (text.length - text.trimEnd().length);
      }
    }
    cursor = Math.max(cursor, hiddenRange.to);
  }
  return first === undefined ? null : {from: first, to: last};
}

/** Expand complete visible headings using only parser-owned source intervals.
 * The caller chooses Edit pointer selections; Source and arbitrary selections
 * do not acquire structural transfer semantics merely by calling other APIs.
 */
export function completeHeadingSelection(state: EditorState, selection: EditorSelection): EditorSelection {
  const minimum = bodyStart(state);
  const ranges = selection.ranges.map(range => {
    if (range.empty || range.from < minimum) return range;
    const semantic = semanticProjectionRanges(state, [range], 0);
    const headings = semantic.blocks.filter(heading => heading.kind === 'heading' && heading.from >= minimum);
    // Hidden prefix/suffix inlines can lie wholly outside the visible selection.
    // Query the complete heading spans before deriving their visible endpoints.
    const inlines = semanticProjectionRanges(state, headings, 0).inlines;
    let from = range.from, to = range.to, includesHeading = false;
    for (const heading of headings) {
      const visible = visibleHeadingRange(state, heading, inlines);
      if (!visible || range.from > visible.from || range.to < visible.to) continue;
      const source = headingSourceRange(state, heading);
      includesHeading = true;
      from = Math.min(from, source.from);
      to = Math.max(to, source.to);
    }
    if (includesHeading && isCompleteLineSelection(state, {from, to})
        && to < state.doc.length && state.doc.lineAt(to).to === to
        && state.doc.sliceString(to - 1, to) !== '\n') to += 1;
    if (from === range.from && to === range.to) return range;
    return range.anchor > range.head ? EditorSelection.range(to, from) : EditorSelection.range(from, to);
  });
  return ranges.every((range, index) => range === selection.ranges[index])
    ? selection : EditorSelection.create(ranges, selection.mainIndex);
}

/** Only complete lines containing an entire parsed heading qualify for block drops. */
export function containsCompleteHeading(state: EditorState, range: SemanticSourceRange): boolean {
  const minimum = bodyStart(state);
  if (range.from < minimum || !isCompleteLineSelection(state, range)) return false;
  return semanticProjectionRanges(state, [range], 0).blocks.some(heading => {
    if (heading.kind !== 'heading' || heading.from < minimum) return false;
    const source = headingSourceRange(state, heading);
    return source.from >= range.from && source.to <= range.to;
  });
}

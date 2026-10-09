import {EditorSelection, findClusterBreak, type EditorState, type Extension, type SelectionRange} from "@codemirror/state";
import {EditorView, keymap} from "@codemirror/view";
import type {EditorMode} from "./protocol";
import {
  projectionRangeAtBoundary,
  projectionRangesIntersecting,
} from "./projection-index";
import {
  selectionActivatesSyntax,
  type ProjectionSourceRange,
} from "./projection-update";
import type {LiveProjectionIndexController} from "./live-projection-index";

/**
 * Owns keyboard traversal across inactive Live Preview projections. It changes
 * only CodeMirror selection; source, history, composition, and projection
 * state remain with the retained EditorState and their existing owners.
 */
export function createLiveProjectionNavigation(options: {
  mode(state: EditorState): EditorMode;
  projections: LiveProjectionIndexController;
  mermaidPresentations(state: EditorState): readonly ProjectionSourceRange[];
  imagePresentations(state: EditorState): readonly ProjectionSourceRange[];
}): {extension: Extension} {
  function blockRanges(state: EditorState) {
    return [
      ...options.projections.index(state).blockRanges.filter(range => range.kind !== "callout"),
      ...options.mermaidPresentations(state).map(({from, to}) => ({
        from,
        to,
        kind: "mermaid" as const,
      })),
      ...options.imagePresentations(state)
        .map(({from, to}) => ({from, to, kind: "image" as const})),
    ].sort((left, right) => left.from - right.from || left.to - right.to);
  }

  function horizontalRangeAt(
    state: EditorState,
    offset: number,
    forward: boolean,
  ) {
    const index = options.projections.index(state);
    const boundary = forward ? "start" : "end";
    const blockRange = projectionRangeAtBoundary(
      index.blockRanges.filter(range => range.kind !== "callout"), offset, boundary);
    const listPrefixRange = projectionRangeAtBoundary(
      index.listPrefixRanges,
      offset,
      boundary,
    );
    const mermaidRange = projectionRangeAtBoundary(
      options.mermaidPresentations(state),
      offset,
      boundary,
    );
    const inlineLinkRange = projectionRangeAtBoundary(
      index.syntax.inlines.filter((candidate) => candidate.kind === "wikilink"),
      offset,
      boundary,
    );
    const candidates = [
      blockRange,
      listPrefixRange ? {...listPrefixRange, kind: "listPrefix" as const} : null,
      mermaidRange ? {...mermaidRange, kind: "mermaid" as const} : null,
      inlineLinkRange,
    ].filter((candidate) => candidate !== null);
    return candidates.sort((left, right) =>
      left.from - right.from || left.to - right.to,
    )[0] ?? null;
  }

  /**
   * A projected list marker is an atomic replacement while the line is
   * inactive. Once the caret enters its source prefix, the prefix becomes
   * ordinary editable text. CodeMirror owns character movement and its
   * selection metadata through that transition. At the trailing edge the
   * normal command may leave toward prose; at the
   * leading edge it may leave toward the previous line.
   */
  function stepInsideListPrefix(
    view: EditorView,
    forward: boolean,
    extend: boolean,
  ): boolean | null {
    const selection = view.state.selection.main;
    if (!selection.empty) return null;
    const index = options.projections.index(view.state);
    const nearby = projectionRangesIntersecting(
      index.listPrefixRanges,
      Math.max(0, selection.head - 1),
      selection.head + 1,
    );
    const prefix = nearby.find((range) =>
      selection.head >= range.from && selection.head <= range.to);
    if (!prefix) return null;

    if (forward ? selection.head >= prefix.to : selection.head <= prefix.from) return null;
    const moved = view.moveByChar(selection, forward);

    view.dispatch({
      selection: selectionForMove(selection, moved, extend),
      scrollIntoView: true,
      userEvent: "select",
    });
    return true;
  }

  function selectionForMove(start: SelectionRange, moved: SelectionRange, extend: boolean) {
    return EditorSelection.create([extend
      ? EditorSelection.range(start.anchor, moved.head, moved.goalColumn,
        moved.bidiLevel ?? undefined, moved.assoc)
      : moved]);
  }

  function sourceEntryHead(state: EditorState, projection: ProjectionSourceRange, forward: boolean) {
    if (forward) return projection.from;
    const line = state.doc.lineAt(projection.to);
    const previous = projection.to === line.from
      ? projection.to - 1
      : line.from + findClusterBreak(line.text, projection.to - line.from, false);
    return Math.max(projection.from, previous);
  }

  function revealForVerticalMove(
    view: EditorView,
    forward: boolean,
    extend: boolean,
  ) {
    if (options.mode(view.state) !== "livePreview" || view.composing || view.compositionStarted
        || view.state.selection.ranges.length !== 1) return false;
    const selection = view.state.selection.main;
    // Plain movement collapses an existing selection through CodeMirror's
    // normal commands rather than entering a neighboring projection.
    if (!extend && !selection.empty) return false;
    const moved = view.moveVertically(selection, forward);
    // A projected move may land on the incoming boundary instead of skipping
    // the whole source range. Include that endpoint in either direction.
    const crossed = projectionRangesIntersecting(
      blockRanges(view.state),
      Math.max(0, Math.min(selection.head, moved.head) - 1),
      Math.max(selection.head, moved.head) + 1,
    ).filter((candidate) => {
      const alreadyActive = view.state.selection.ranges.some((range) =>
        selectionActivatesSyntax(range, candidate));
      if (alreadyActive) return false;
      return forward
        ? selection.head <= candidate.from && moved.head >= candidate.from
        : selection.head >= candidate.to && moved.head <= candidate.to;
    });
    const projection = forward ? crossed[0] : crossed.at(-1);
    if (!projection) return false;

    const sourceHead = sourceEntryHead(view.state, projection, forward);
    const originalCoords = view.coordsAtPos(selection.head, selection.assoc || 1);
    const contentLeft = view.contentDOM.getBoundingClientRect().left;
    const goalColumn = selection.goalColumn ?? moved.goalColumn
      ?? (originalCoords?.left ?? contentLeft) - contentLeft;
    const sourceCursor = EditorSelection.cursor(sourceHead, forward ? 1 : -1,
      moved.bidiLevel ?? undefined, goalColumn);
    view.dispatch({
      selection: selectionForMove(selection, sourceCursor, extend),
      scrollIntoView: true,
      userEvent: "select",
    });
    const expectedDocument = view.state.doc;
    const expectedSelection = view.state.selection;
    const current = () => !view.composing && !view.compositionStarted
      && options.mode(view.state) === "livePreview"
      && view.state.doc === expectedDocument
      && view.state.selection.eq(expectedSelection, true);
    view.requestMeasure({
      read: () => {
        if (!current()) return null;
        const line = view.state.doc.lineAt(sourceHead);
        const lineEdge = forward ? line.from : line.to;
        const coords = view.coordsAtPos(lineEdge);
        if (!coords) return sourceCursor;
        const measuredHead = view.posAtCoords({
          x: view.contentDOM.getBoundingClientRect().left + goalColumn,
          y: (coords.top + coords.bottom) / 2,
        }) ?? sourceHead;
        return EditorSelection.cursor(measuredHead, measuredHead === line.to ? -1 : 1,
          moved.bidiLevel ?? undefined, goalColumn);
      },
      write: (measuredCursor) => {
        if (!measuredCursor) return;
        // CodeMirror forbids transactions during a measure write. Commit
        // after that cycle, rechecking authority after any intervening input.
        queueMicrotask(() => {
          if (!current()) return;
          view.dispatch({
            selection: selectionForMove(selection, measuredCursor, extend),
            scrollIntoView: true,
            userEvent: "select",
          });
        });
      },
    });
    return true;
  }

  function revealForHorizontalMove(
    view: EditorView,
    forward: boolean,
    extend: boolean,
  ) {
    if (options.mode(view.state) !== "livePreview" || view.composing || view.compositionStarted
        || view.state.selection.ranges.length !== 1) return false;
    const selection = view.state.selection.main;
    if (!extend && !selection.empty) return false;
    const listStep = stepInsideListPrefix(view, forward, extend);
    if (listStep !== null) return listStep;
    const projection = horizontalRangeAt(view.state, selection.head, forward);
    if (!projection) return false;
    const alreadyActive = selectionActivatesSyntax(selection, projection);
    if (alreadyActive) return false;
    const head = forward
      ? projection.from
      : sourceEntryHead(view.state, projection, false);
    // A Shift selection ending at the incoming edge has not activated the
    // source yet. Let CodeMirror extend it rather than consuming a no-op.
    if (head === selection.head) return false;
    view.dispatch({
      selection: {anchor: extend ? selection.anchor : head, head},
      scrollIntoView: true,
      userEvent: "select",
    });
    return true;
  }

  return {
    extension: keymap.of([
      {key: "ArrowDown", run: (view) => revealForVerticalMove(view, true, false)},
      {key: "Shift-ArrowDown", run: (view) => revealForVerticalMove(view, true, true)},
      {key: "ArrowUp", run: (view) => revealForVerticalMove(view, false, false)},
      {key: "Shift-ArrowUp", run: (view) => revealForVerticalMove(view, false, true)},
      {key: "ArrowRight", run: (view) => revealForHorizontalMove(view, true, false)},
      {key: "Shift-ArrowRight", run: (view) => revealForHorizontalMove(view, true, true)},
      {key: "ArrowLeft", run: (view) => revealForHorizontalMove(view, false, false)},
      {key: "Shift-ArrowLeft", run: (view) => revealForHorizontalMove(view, false, true)},
    ]),
  };
}

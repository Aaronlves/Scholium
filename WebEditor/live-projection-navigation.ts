import type {EditorState, Extension} from "@codemirror/state";
import {EditorView, keymap} from "@codemirror/view";
import type {EditorMode} from "./protocol";
import {
  projectionRangeAtBoundary,
  projectionRangesIntersecting,
} from "./projection-index";
import {
  selectionActivatesCallout,
  selectionIntersectsProjection,
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
}): {extension: Extension} {
  function blockRanges(state: EditorState) {
    return [
      ...options.projections.index(state).blockRanges,
      ...options.mermaidPresentations(state).map(({from, to}) => ({
        from,
        to,
        kind: "mermaid" as const,
      })),
    ].sort((left, right) => left.from - right.from || left.to - right.to);
  }

  function horizontalRangeAt(
    state: EditorState,
    offset: number,
    forward: boolean,
  ) {
    const index = options.projections.index(state);
    const boundary = forward ? "start" : "end";
    const blockRange = projectionRangeAtBoundary(index.blockRanges, offset, boundary);
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
      index.syntax.inlines.filter((candidate) =>
        candidate.kind === "wikilink" || candidate.kind === "vectorLink"),
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

  function revealForVerticalMove(
    view: EditorView,
    forward: boolean,
    extend: boolean,
  ) {
    if (options.mode(view.state) !== "livePreview" || view.composing) return false;
    const selection = view.state.selection.main;
    const moved = view.moveVertically(selection, forward);
    const crossed = projectionRangesIntersecting(
      blockRanges(view.state),
      Math.min(selection.head, moved.head),
      Math.max(selection.head, moved.head) + 1,
    ).filter((candidate) => {
      const alreadyActive = view.state.selection.ranges.some((range) =>
        candidate.kind === "callout"
          ? selectionActivatesCallout(range, candidate)
          : selectionIntersectsProjection(range, candidate));
      if (alreadyActive) return false;
      return forward
        ? selection.head <= candidate.from && moved.head >= candidate.to
        : selection.head >= candidate.to && moved.head <= candidate.from;
    });
    const projection = forward ? crossed[0] : crossed.at(-1);
    if (!projection) return false;

    const isCallout = projection.kind === "callout";
    const sourceHead = forward
      ? projection.from
      : isCallout ? projection.to : Math.max(projection.from, projection.to - 1);
    const originalCoords = view.coordsAtPos(selection.head);
    const desiredX = originalCoords?.left ?? originalCoords?.right ?? 0;
    const anchor = extend ? selection.anchor : sourceHead;
    view.dispatch({
      selection: {anchor, head: sourceHead},
      scrollIntoView: true,
    });
    if (isCallout) {
      view.requestMeasure();
      return true;
    }
    view.requestMeasure({
      read: () => {
        const line = view.state.doc.lineAt(sourceHead);
        const lineEdge = forward ? line.from : line.to;
        const coords = view.coordsAtPos(lineEdge);
        if (!coords) return sourceHead;
        return view.posAtCoords({
          x: desiredX,
          y: (coords.top + coords.bottom) / 2,
        }) ?? sourceHead;
      },
      write: (measuredHead) => {
        if (view.state.selection.main.head !== sourceHead) return;
        view.dispatch({
          selection: {anchor, head: measuredHead},
          scrollIntoView: true,
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
    if (options.mode(view.state) !== "livePreview" || view.composing) return false;
    const selection = view.state.selection.main;
    const projection = horizontalRangeAt(view.state, selection.head, forward);
    if (!projection) return false;
    const alreadyActive = projection.kind === "callout"
      ? selectionActivatesCallout(selection, projection)
      : selectionIntersectsProjection(selection, projection);
    const isProjectedLink = projection.kind === "wikilink"
      || projection.kind === "vectorLink";
    // Forward traversal treats a projected Wikilink as one object. Backward
    // traversal from its end still exposes the authored closing delimiter.
    if (alreadyActive
        && !(isProjectedLink && forward && selection.head === projection.from)) {
      return false;
    }
    const head = forward
      ? isProjectedLink ? projection.to : projection.from
      : projection.kind === "callout"
        ? projection.to
        : Math.max(projection.from, projection.to - 1);
    view.dispatch({
      selection: {anchor: extend ? selection.anchor : head, head},
      scrollIntoView: true,
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

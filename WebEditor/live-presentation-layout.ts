import {StateEffect} from "@codemirror/state";
import {EditorView, ViewPlugin, type ViewUpdate} from "@codemirror/view";
import {
  readLiveCursorGeometry,
  writeLiveCursorGeometry,
} from "./live-cursor-geometry";

/**
 * A presentation owner uses this effect when a source-neutral decoration
 * change can alter block geometry. The affected source range is a hint for
 * choosing a viewport anchor outside the block being exchanged; it is not a
 * second source or selection authority.
 */
export interface PresentationLayoutRange {
  readonly from: number;
  readonly to: number;
}

export const preserveLivePresentationLayout = StateEffect.define<PresentationLayoutRange>({
  map: (value, changes) => ({
    from: changes.mapPos(value.from),
    to: changes.mapPos(value.to),
  }),
});

interface LayoutAnchor {
  readonly from: number;
  readonly top: number;
  readonly scrollTop: number;
  readonly epoch: number;
}

function lineElementAt(view: EditorView, position: number): HTMLElement | null {
  for (const assoc of [1, -1] as const) {
    try {
      const point = view.domAtPos(position, assoc);
      const element = point.node.nodeType === Node.ELEMENT_NODE
        ? point.node as Element
        : point.node.parentElement;
      const line = element?.closest<HTMLElement>(".cm-line");
      if (line) return line;
    } catch {
      // A line can leave the viewport between the block and DOM measurements.
    }
  }
  return null;
}

function intersects(
  from: number,
  to: number,
  range: PresentationLayoutRange,
) {
  return from < range.to && to > range.from;
}

function captureLayoutAnchor(
  view: EditorView,
  epoch: number,
  affected: readonly PresentationLayoutRange[],
): LayoutAnchor | null {
  const scroll = view.scrollDOM;
  const rect = scroll.getBoundingClientRect();
  // `viewportLineBlocks` exposes the already-measured view state and is safe
  // during ViewPlugin.update. `lineBlockAtHeight` calls readMeasured(), which
  // CodeMirror rejects while it is applying a state update. Both the probe and
  // block tops use documentTop-relative coordinates, so adding scrollTop here
  // would count the scroll offset twice.
  const probeHeight = Math.max(0, rect.top + 1 - view.documentTop);
  const blocks = view.viewportLineBlocks;
  if (!blocks.length) return null;
  const containing = blocks.findIndex(candidate =>
    candidate.top <= probeHeight && candidate.bottom > probeHeight);
  const firstAfter = blocks.findIndex(candidate => candidate.bottom > probeHeight);
  const start = containing >= 0
    ? containing
    : firstAfter >= 0 ? firstAfter : blocks.length - 1;
  const ordered = blocks.slice(start).concat(blocks.slice(0, start));
  const stable = affected.length === 0
    ? ordered
    : ordered.filter(candidate => !affected.some(range =>
      intersects(candidate.from, candidate.to, range)));
  const candidates = stable.length > 0 ? stable : ordered;
  for (const candidate of candidates) {
    const line = lineElementAt(view, candidate.from);
    if (line) {
      return {
        from: candidate.from,
        top: line.getBoundingClientRect().top,
        scrollTop: scroll.scrollTop,
        epoch,
      };
    }
  }
  return null;
}

function applyLayoutAnchor(view: EditorView, anchor: LayoutAnchor): number {
  const line = lineElementAt(view, anchor.from);
  if (!line) return 0;
  const delta = line.getBoundingClientRect().top - anchor.top;
  if (Math.abs(delta) < 0.25) return 0;
  const scroll = view.scrollDOM;
  const maximum = Math.max(0, scroll.scrollHeight - scroll.clientHeight);
  const before = scroll.scrollTop;
  const after = Math.max(0, Math.min(maximum, before + delta));
  if (Math.abs(after - before) >= 0.25) scroll.scrollTop = after;
  return after - before;
}

function layoutRanges(update: ViewUpdate): PresentationLayoutRange[] {
  return update.transactions.flatMap(transaction => transaction.effects.flatMap(effect =>
    effect.is(preserveLivePresentationLayout) ? [effect.value] : []));
}

/**
 * Owns presentation-only geometry continuity for the complete Live surface.
 * Projection fields retain semantic state; this coordinator is the sole owner
 * of the cross-projection viewport correction and never dispatches source or
 * selection transactions.
 */
export const livePresentationLayout = ViewPlugin.fromClass(class {
  private layoutEpoch = 0;
  private destroyed = false;
  private reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  private resize: ResizeObserver;

  constructor(readonly view: EditorView) {
    this.reduced.addEventListener("change", this.invalidate);
    this.resize = new ResizeObserver(() => this.invalidate());
    this.resize.observe(view.scrollDOM);
    view.scrollDOM.addEventListener("scroll", this.invalidate, {passive: true});
  }

  readonly invalidate = () => {
    this.layoutEpoch += 1;
  };

  private schedule(anchor: LayoutAnchor) {
    queueMicrotask(() => {
      if (this.destroyed || anchor.epoch !== this.layoutEpoch || this.view.composing) return;
      const scroll = this.view.scrollDOM;
      if (Math.abs(scroll.scrollTop - anchor.scrollTop) >= 0.25) return;
      const scrollCorrection = applyLayoutAnchor(this.view, anchor);
      if (scrollCorrection === 0) return;
      const cursor = readLiveCursorGeometry(this.view);
      writeLiveCursorGeometry(this.view, cursor && {
        ...cursor,
        top: cursor.top - scrollCorrection,
        bottom: cursor.bottom - scrollCorrection,
      });
    });
  }

  update(update: ViewUpdate) {
    if (!update.docChanged && !update.selectionSet && update.transactions.length === 0) return;
    this.layoutEpoch += 1;
    if (this.view.composing || update.docChanged
        || update.transactions.some(transaction => transaction.scrollIntoView)) return;

    const affected = layoutRanges(update);
    const explicitLayout = affected.length > 0;
    const selectionLayout = update.selectionSet
      && update.transactions.every(transaction => transaction.effects.length === 0);
    if (!explicitLayout && !selectionLayout) return;

    const anchor = captureLayoutAnchor(this.view, this.layoutEpoch, affected);
    if (!anchor) return;
    // This request is deliberately installed by the shared coordinator. Its
    // write runs after projection owners have completed their own measure
    // writes, and only then schedules the source-line anchor correction.
    this.view.requestMeasure({
      key: this,
      read: () => null,
      write: () => this.schedule(anchor),
    });
  }

  destroy() {
    this.destroyed = true;
    this.reduced.removeEventListener("change", this.invalidate);
    this.view.scrollDOM.removeEventListener("scroll", this.invalidate);
    this.resize.disconnect();
  }
}, {eventHandlers: {
  mousedown() { this.invalidate(); },
  compositionstart() { this.invalidate(); },
}});

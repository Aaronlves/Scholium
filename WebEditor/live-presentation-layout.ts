import {StateEffect} from "@codemirror/state";
import {EditorView, ViewPlugin, type ViewUpdate} from "@codemirror/view";
import {
  readLiveCursorGeometry,
  readLiveCursorSurfaceGeometry,
  writeLiveCursorGeometry,
  type LiveCursorGeometry,
  type LiveCursorSurfaceGeometry,
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

interface LayoutCorrection {
  readonly delta: number;
  readonly scrollTop: number;
  readonly maximumScrollTop: number;
  readonly cursor: LiveCursorGeometry | null;
  readonly surface: LiveCursorSurfaceGeometry;
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
  // `viewportLineBlocks` exposes the already-measured view state and is safe
  // during ViewPlugin.update. `lineBlockAtHeight`, `documentTop`, and DOM
  // geometry reads are not safe here because CodeMirror calls plugins before
  // updating its own DOM. The returned order is already viewport order; using
  // the first stable block avoids a second layout read while retaining a
  // source-addressed anchor.
  const blocks = view.viewportLineBlocks;
  if (!blocks.length) return null;
  const stable = affected.length === 0
    ? blocks
    : blocks.filter(candidate => !affected.some(range =>
      intersects(candidate.from, candidate.to, range)));
  const candidates = stable.length > 0 ? stable : blocks;
  for (const candidate of candidates) {
    return {
      from: candidate.from,
      top: candidate.top,
      scrollTop: scroll.scrollTop,
      epoch,
    };
  }
  return null;
}

function readLayoutCorrection(view: EditorView, anchor: LayoutAnchor): LayoutCorrection | null {
  const scroll = view.scrollDOM;
  if (Math.abs(scroll.scrollTop - anchor.scrollTop) >= 0.25) return null;
  let block: ReturnType<EditorView["lineBlockAt"]>;
  try {
    block = view.lineBlockAt(anchor.from);
  } catch {
    return null;
  }
  const delta = block.top - anchor.top;
  if (Math.abs(delta) < 0.25) return null;
  return {
    delta,
    scrollTop: scroll.scrollTop,
    maximumScrollTop: Math.max(0, scroll.scrollHeight - scroll.clientHeight),
    cursor: readLiveCursorGeometry(view),
    surface: readLiveCursorSurfaceGeometry(view),
  };
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
  private correctionKey = {};

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
      // The first measure write runs after projection owners have committed
      // their DOM. Schedule a fresh CodeMirror read/write cycle so the
      // correction observes that final layout and never reads geometry from a
      // write phase.
      this.view.requestMeasure({
        key: this.correctionKey,
        read: () => {
          if (this.destroyed || anchor.epoch !== this.layoutEpoch || this.view.composing) return null;
          return readLayoutCorrection(this.view, anchor);
        },
        write: (correction: LayoutCorrection | null) => {
          if (!correction || this.destroyed || anchor.epoch !== this.layoutEpoch || this.view.composing) return;
          const scroll = this.view.scrollDOM;
          if (Math.abs(scroll.scrollTop - correction.scrollTop) >= 0.25) return;
          const after = Math.max(0, Math.min(
            correction.maximumScrollTop,
            correction.scrollTop + correction.delta,
          ));
          const applied = after - correction.scrollTop;
          if (Math.abs(applied) < 0.25) return;
          scroll.scrollTop = after;
          const scaleY = correction.surface.scaleY;
          writeLiveCursorGeometry(this.view, correction.cursor && {
            ...correction.cursor,
            top: correction.cursor.top - applied * scaleY,
            bottom: correction.cursor.bottom - applied * scaleY,
          }, {
            ...correction.surface,
            scrollTop: correction.surface.scrollTop + applied * scaleY,
          });
        },
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

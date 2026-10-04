import {Direction, type EditorView} from "@codemirror/view";

export interface LiveCursorGeometry {
  readonly left: number;
  readonly top: number;
  readonly bottom: number;
}

export interface LiveCursorSurfaceGeometry {
  readonly outerLeft: number;
  readonly outerRight: number;
  readonly outerTop: number;
  readonly clientWidth: number;
  readonly scaleX: number;
  readonly scaleY: number;
  readonly scrollLeft: number;
  readonly scrollTop: number;
  readonly direction: Direction;
}

/**
 * CodeMirror's cursor layer normally measures positions when a transaction or
 * vertical geometry update arrives. Live Preview also changes inline geometry
 * through CSS/Web Animations, which does not necessarily produce either kind
 * of CodeMirror update. Read the authoritative source position back through
 * the current DOM so the cursor follows that presentation-only movement.
 */
export function readLiveCursorGeometry(view: EditorView): LiveCursorGeometry | null {
  const selection = view.state.selection.main;
  if (!selection.empty) return null;

  // A collapsed DOM Range loses the approached side of a soft wrap in
  // WebKit, placing an end-of-row caret at the next row's start. CodeMirror
  // owns wrap affinity, grapheme and bidi geometry through SelectionRange.
  const rect = view.coordsAtPos(selection.head, selection.assoc || 1);
  if (!rect) return null;
  return {left: rect.left, top: rect.top, bottom: rect.bottom};
}

/** Read the surface geometry during a CodeMirror measure read phase. */
export function readLiveCursorSurfaceGeometry(view: EditorView): LiveCursorSurfaceGeometry {
  const outer = view.scrollDOM.getBoundingClientRect();
  const scaleX = (view as EditorView & {scaleX?: number}).scaleX ?? 1;
  const scaleY = (view as EditorView & {scaleY?: number}).scaleY ?? 1;
  return {
    outerLeft: outer.left,
    outerRight: outer.right,
    outerTop: outer.top,
    clientWidth: view.scrollDOM.clientWidth,
    scaleX,
    scaleY,
    scrollLeft: view.scrollDOM.scrollLeft * scaleX,
    scrollTop: view.scrollDOM.scrollTop * scaleY,
    direction: view.textDirection,
  };
}

/**
 * Apply a measured source caret position to CodeMirror's own primary cursor
 * marker. Selection authority stays in EditorState; this only refreshes the
 * marker's screen geometry while an animated projection is changing layout.
 */
export function writeLiveCursorGeometry(
  view: EditorView,
  geometry: LiveCursorGeometry | null,
  surface: LiveCursorSurfaceGeometry,
) {
  if (!geometry) return;
  const cursor = view.scrollDOM.querySelector<HTMLElement>(".cm-cursor-primary");
  if (!cursor) return;

  const baseLeft = surface.direction === Direction.LTR
    ? surface.outerLeft - surface.scrollLeft
    : surface.outerRight - surface.clientWidth * surface.scaleX - surface.scrollLeft;
  const baseTop = surface.outerTop - surface.scrollTop;

  cursor.style.left = `${(geometry.left - baseLeft) / surface.scaleX}px`;
  cursor.style.top = `${(geometry.top - baseTop) / surface.scaleY}px`;
  cursor.style.height = `${(geometry.bottom - geometry.top) / surface.scaleY}px`;
}

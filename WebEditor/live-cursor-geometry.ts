import {Direction, type EditorView} from "@codemirror/view";

export interface LiveCursorGeometry {
  readonly left: number;
  readonly top: number;
  readonly bottom: number;
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

  const assoc = selection.assoc || 1;
  let rect: DOMRect | null = null;
  try {
    const line = view.state.doc.lineAt(selection.head);
    // At a line end, CodeMirror can expose the parent boundary after the
    // line's DOM node. A collapsed Range at that boundary reports the line
    // start in WebKit, so read the text-side DOM point instead.
    const side = selection.head === line.to
      ? -1
      : selection.head === line.from ? 1 : assoc;
    const point = view.domAtPos(selection.head, side);
    const range = view.dom.ownerDocument.createRange();
    range.setStart(point.node, point.offset);
    range.collapse(true);
    rect = range.getBoundingClientRect();
  } catch {
    rect = null;
  }

  if (!rect || rect.height < 1 || !Number.isFinite(rect.left)) {
    const fallback = view.coordsAtPos(selection.head, assoc);
    if (!fallback) return null;
    return {left: fallback.left, top: fallback.top, bottom: fallback.bottom};
  }
  return {left: rect.left, top: rect.top, bottom: rect.bottom};
}

/**
 * Apply a measured source caret position to CodeMirror's own primary cursor
 * marker. Selection authority stays in EditorState; this only refreshes the
 * marker's screen geometry while an animated projection is changing layout.
 */
export function writeLiveCursorGeometry(
  view: EditorView,
  geometry: LiveCursorGeometry | null,
) {
  if (!geometry) return;
  const cursor = view.scrollDOM.querySelector<HTMLElement>(".cm-cursor-primary");
  if (!cursor) return;

  const outer = view.scrollDOM.getBoundingClientRect();
  const scaleX = (view as EditorView & {scaleX?: number}).scaleX ?? 1;
  const scaleY = (view as EditorView & {scaleY?: number}).scaleY ?? 1;
  const scrollLeft = view.scrollDOM.scrollLeft * scaleX;
  const scrollTop = view.scrollDOM.scrollTop * scaleY;
  const baseLeft = view.textDirection === Direction.LTR
    ? outer.left - scrollLeft
    : outer.right - view.scrollDOM.clientWidth * scaleX - scrollLeft;
  const baseTop = outer.top - scrollTop;

  cursor.style.left = `${(geometry.left - baseLeft) / scaleX}px`;
  cursor.style.top = `${(geometry.top - baseTop) / scaleY}px`;
  cursor.style.height = `${(geometry.bottom - geometry.top) / scaleY}px`;
}

import {Direction, type EditorView} from "@codemirror/view";
import type {EditorState} from "@codemirror/state";

interface LiveCursorPosition {
  readonly primary: boolean;
  readonly left: number;
  readonly top: number;
  readonly bottom: number;
}

export interface LiveCursorGeometry {
  readonly state: EditorState;
  readonly cursors: readonly LiveCursorPosition[];
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
  const state = view.state;
  // A collapsed DOM Range loses the approached side of a soft wrap in
  // WebKit, placing an end-of-row caret at the next row's start. CodeMirror
  // owns wrap affinity, grapheme and bidi geometry through SelectionRange.
  // The editor sets drawRangeCursor:false. Refresh every collapsed range,
  // including secondary carets displaced by the same revealed prefix.
  const cursors: LiveCursorPosition[] = [];
  for (const selection of state.selection.ranges) {
    if (!selection.empty) continue;
    const rect = view.coordsAtPos(selection.head, selection.assoc || 1);
    if (rect) cursors.push({
      primary: selection === state.selection.main,
      left: rect.left,
      top: rect.top,
      bottom: rect.bottom,
    });
  }
  return cursors.length > 0 ? {state, cursors} : null;
}

/** Read the surface geometry during a CodeMirror measure read phase. */
export function readLiveCursorSurfaceGeometry(view: EditorView): LiveCursorSurfaceGeometry {
  const outer = view.scrollDOM.getBoundingClientRect();
  const {scaleX, scaleY} = view;
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
 * Refresh CodeMirror's existing cursor markers after a presentation-only
 * layout write. Never create markers or dispatch a selection transaction.
 * Its layer already applies inverse scaling, so marker coordinates retain
 * the screen-pixel deltas used by CodeMirror's RectangleMarker.forRange.
 */
export function writeLiveCursorGeometry(
  view: EditorView,
  geometry: LiveCursorGeometry | null,
  surface: LiveCursorSurfaceGeometry,
) {
  if (!geometry || geometry.state !== view.state) return;
  const cursors = [...view.scrollDOM.querySelectorAll<HTMLElement>(".cm-cursorLayer > .cm-cursor")];
  // A pending native layer refresh can replace its marker set after our read.
  // Fail closed rather than applying old coordinates to another source caret.
  if (cursors.length !== geometry.cursors.length || cursors.some((cursor, index) =>
    cursor.classList.contains("cm-cursor-primary") !== geometry.cursors[index].primary)) return;

  const baseLeft = surface.direction === Direction.LTR
    ? surface.outerLeft - surface.scrollLeft
    : surface.outerRight - surface.clientWidth * surface.scaleX - surface.scrollLeft;
  const baseTop = surface.outerTop - surface.scrollTop;

  cursors.forEach((cursor, index) => {
    const position = geometry.cursors[index];
    cursor.style.left = `${position.left - baseLeft}px`;
    cursor.style.top = `${position.top - baseTop}px`;
    cursor.style.height = `${position.bottom - position.top}px`;
  });
}

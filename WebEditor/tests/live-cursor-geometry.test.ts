import {EditorSelection, EditorState, type SelectionRange} from "@codemirror/state";
import {Direction, RectangleMarker, type EditorView} from "@codemirror/view";
import {parseHTML} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {
  readLiveCursorGeometry,
  readLiveCursorSurfaceGeometry,
  writeLiveCursorGeometry,
} from "../live-cursor-geometry";

function cursorView(ranges: readonly SelectionRange[], mainIndex = 0,
  direction = Direction.LTR, scaleX = 1, scaleY = 1, unmountedHead?: number) {
  const state = EditorState.create({
    doc: "Ordinary 中文 e\u0301 🧭 prose. ".repeat(20),
    selection: EditorSelection.create(ranges, mainIndex),
    extensions: [EditorState.allowMultipleSelections.of(true)],
  });
  const {document} = parseHTML("<html><body><div id='scroll'><div class='cm-cursorLayer'></div></div></body></html>");
  const scroll = document.querySelector<HTMLElement>("#scroll")!;
  Object.defineProperties(scroll, {
    clientWidth: {value: 400},
    scrollLeft: {value: direction === Direction.LTR ? 15 : -15},
    scrollTop: {value: 40},
  });
  scroll.getBoundingClientRect = () => ({left: 30, right: 30 + 400 * scaleX,
    top: 20, bottom: 420, width: 400 * scaleX, height: 400, x: 30, y: 20, toJSON: () => ({})});
  const coordsAtPos = vi.fn((head: number, assoc: number) => head === unmountedHead
    ? null
    : {left: (60 + head + assoc) * scaleX, right: (60 + head + assoc) * scaleX,
      top: 100 * scaleY, bottom: 124 * scaleY});
  const view = {state, scrollDOM: scroll, coordsAtPos, scaleX, scaleY, textDirection: direction} as unknown as EditorView;
  const expected: RectangleMarker[] = [];
  const layer = scroll.querySelector<HTMLElement>(".cm-cursorLayer")!;
  for (const range of state.selection.ranges) {
    if (!range.empty) continue;
    const className = range === state.selection.main
      ? "cm-cursor cm-cursor-primary" : "cm-cursor cm-cursor-secondary";
    for (const marker of RectangleMarker.forRange(view, className, range)) {
      expected.push(marker);
      const node = document.createElement("div");
      node.className = className;
      layer.append(node);
    }
  }
  coordsAtPos.mockClear();
  return {view, expected, nodes: [...layer.children] as HTMLElement[], coordsAtPos};
}

function expectNativeMarkerGeometry(nodes: HTMLElement[], expected: readonly RectangleMarker[]) {
  expect(nodes.map(node => [node.style.left, node.style.top, node.style.height]))
    .toEqual(expected.map(marker => [`${marker.left}px`, `${marker.top}px`, `${marker.height}px`]));
}

describe("Live caret geometry after source-neutral layout", () => {
  it.each([
    [Direction.LTR, 1, 1], [Direction.RTL, 1, 1],
    [Direction.LTR, 1.5, 2], [Direction.RTL, 1.5, 2],
  ])("matches the native cursor layer at direction %s and scale %s/%s", (direction, scaleX, scaleY) => {
    const {view, nodes, expected} = cursorView([EditorSelection.cursor(20, -1)], 0,
      direction, scaleX, scaleY);
    const state = view.state;
    const source = state.doc.toString();
    writeLiveCursorGeometry(view, readLiveCursorGeometry(view), readLiveCursorSurfaceGeometry(view));
    expectNativeMarkerGeometry(nodes, expected);
    expect(view.state).toBe(state);
    expect(view.state.doc.toString()).toBe(source);
  });

  it("refreshes secondary carets while retaining each wrap affinity and primary identity", () => {
    const {view, nodes, expected, coordsAtPos} = cursorView([
      EditorSelection.cursor(20, -1), EditorSelection.cursor(60, 1), EditorSelection.cursor(100, -1),
    ], 1);
    writeLiveCursorGeometry(view, readLiveCursorGeometry(view), readLiveCursorSurfaceGeometry(view));
    expect(coordsAtPos.mock.calls).toEqual([[20, -1], [60, 1], [100, -1]]);
    expectNativeMarkerGeometry(nodes, expected);
  });

  it("retains secondary carets when the main range is nonempty and skips unmounted carets", () => {
    const {view, nodes, expected} = cursorView([
      EditorSelection.cursor(20), EditorSelection.range(60, 75), EditorSelection.cursor(100),
      EditorSelection.cursor(140),
    ], 1, Direction.LTR, 1, 1, 140);
    writeLiveCursorGeometry(view, readLiveCursorGeometry(view), readLiveCursorSurfaceGeometry(view));
    expect(nodes).toHaveLength(2);
    expectNativeMarkerGeometry(nodes, expected);
  });

  it("does not apply a measured old selection to a newer editor state", () => {
    const {view, nodes} = cursorView([EditorSelection.cursor(20)]);
    const measured = readLiveCursorGeometry(view);
    const surface = readLiveCursorSurfaceGeometry(view);
    Object.defineProperty(view, "state", {value: view.state.update({selection: {anchor: 21}}).state});
    writeLiveCursorGeometry(view, measured, surface);
    expect(nodes[0].style.left).toBe("");
  });

  it("waits for the native marker set when pending drawing changes primary identity", () => {
    const {view, nodes} = cursorView([EditorSelection.cursor(20), EditorSelection.cursor(60)], 1);
    const measured = readLiveCursorGeometry(view);
    nodes[0].classList.add("cm-cursor-primary");
    writeLiveCursorGeometry(view, measured, readLiveCursorSurfaceGeometry(view));
    expect(nodes.every(node => !node.style.left)).toBe(true);
  });
});

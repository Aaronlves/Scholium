import {
  EditorSelection,
  EditorState,
  Transaction,
  type SelectionRange,
  type TransactionSpec,
} from "@codemirror/state";
import {Direction, keymap, type EditorView} from "@codemirror/view";
import {selectCharRight} from "@codemirror/commands";
import {describe, expect, it, vi} from "vitest";
import {createLiveProjectionNavigation} from "../live-projection-navigation";
import type {LiveProjectionIndexController} from "../live-projection-index";
import type {EditorMode} from "../protocol";

const source = "abcdefghij\n\n$$\nx + y\n$$\n\nabcdefghij";
const block = {from: source.indexOf("$$"), to: source.lastIndexOf("$$") + 2, kind: "math"};

function navigation(options: {
  doc?: string;
  selection: EditorSelection;
  blocks?: readonly {from: number; to: number; kind: string}[];
  lists?: readonly {from: number; to: number}[];
  links?: readonly {from: number; to: number; kind: string}[];
  images?: readonly {from: number; to: number}[];
}) {
  let mode: EditorMode = "livePreview";
  const controller = createLiveProjectionNavigation({
    mode: () => mode,
    projections: {index: () => ({
      blockRanges: options.blocks ?? [block],
      listPrefixRanges: options.lists ?? [],
      syntax: {inlines: options.links ?? []},
    })} as unknown as LiveProjectionIndexController,
    mermaidPresentations: () => [],
    imagePresentations: () => options.images ?? [],
  });
  let state = EditorState.create({
    doc: options.doc ?? source,
    selection: options.selection,
    extensions: [EditorState.allowMultipleSelections.of(true), controller.extension],
  });
  const pending: {
    read: () => SelectionRange | null;
    write: (range: SelectionRange | null) => void;
  }[] = [];
  const dispatch = vi.fn((spec: TransactionSpec | Transaction) => {
    state = spec instanceof Transaction ? spec.state : state.update(spec).state;
  });
  const view = {
    get state() { return state; },
    composing: false,
    dispatch,
    contentDOM: {getBoundingClientRect: () => ({left: 10})},
    coordsAtPos: vi.fn((_position: number, _side?: number) =>
      ({left: 40, right: 40, top: 20, bottom: 40})),
    posAtCoords: vi.fn(() => block.from + 1),
    moveVertically: vi.fn((start: SelectionRange, forward: boolean) =>
      EditorSelection.cursor(forward ? block.to + 2 : block.from - 2,
        forward ? -1 : 1, 0, start.goalColumn ?? 140)),
    moveByChar: vi.fn((start: SelectionRange, forward: boolean) =>
      EditorSelection.cursor(start.head + (forward ? 1 : -1), -1, 0)),
    textDirectionAt: () => Direction.LTR,
    requestMeasure: (measure: typeof pending[number]) => pending.push(measure),
  };
  return {
    view,
    dispatch,
    pending,
    change(spec: TransactionSpec) { state = state.update(spec).state; },
    mode(value: EditorMode) { mode = value; },
    run(key: string) {
      const binding = state.facet(keymap).flat().find(binding => binding.key === key);
      if (!binding?.run) throw new Error(`Missing navigation binding: ${key}`);
      return binding.run(view as unknown as EditorView);
    },
    async measure() {
      const measure = pending.shift();
      if (!measure) throw new Error("No projected-entry measurement");
      measure.write(measure.read());
      await Promise.resolve();
    },
  };
}

describe("Live Preview keyboard projection entry", () => {
  it("enters admitted image blocks vertically through the existing measured source handoff", async () => {
    const imageSource = "Before.\n\n![Alt](Attachments/a.png)\n\nAfter.";
    const from = imageSource.indexOf("![Alt]"), to = imageSource.indexOf("\n\nAfter");
    const vertical = navigation({doc: imageSource, blocks: [], images: [{from, to}],
      selection: EditorSelection.single(from - 1)});
    vertical.view.moveVertically.mockReturnValue(EditorSelection.cursor(to + 1));
    vertical.view.posAtCoords.mockReturnValue(from + 4);
    expect(vertical.run("ArrowDown")).toBe(true);
    await vertical.measure();
    expect(vertical.view.state.selection.main).toMatchObject({anchor: from + 4, head: from + 4});
    expect(vertical.view.state.doc.toString()).toBe(imageSource);
  });

  it.each([true, false])("keeps plain vertical entry collapsed and retains its horizontal goal (down: %s)", async forward => {
    const head = forward ? 5 : block.to + 5;
    const harness = navigation({selection: EditorSelection.create([
      EditorSelection.cursor(head, -1, 0, 140),
    ])});
    const measuredHead = forward ? block.from + 1 : block.to - 2;
    harness.view.posAtCoords.mockReturnValue(measuredHead);

    expect(harness.run(forward ? "ArrowDown" : "ArrowUp")).toBe(true);
    expect(harness.view.state.selection.main.empty).toBe(true);
    expect(harness.view.state.selection.main.goalColumn).toBe(140);
    await harness.measure();

    expect(harness.view.state.selection.main).toMatchObject({
      anchor: measuredHead, head: measuredHead, empty: true, goalColumn: 140, bidiLevel: 0,
    });
    expect(harness.view.posAtCoords).toHaveBeenCalledWith({x: 150, y: 30});
    expect(harness.view.coordsAtPos).toHaveBeenCalledWith(head, -1);
    expect(harness.view.state.doc.toString()).toBe(source);
    expect(harness.dispatch.mock.calls.every(([spec]) =>
      spec instanceof Transaction || spec.userEvent === "select")).toBe(true);
  });

  it.each([true, false])("keeps the original Shift selection anchor through measured entry (down: %s)", async forward => {
    const head = forward ? 5 : block.to + 5;
    const anchor = forward ? 0 : source.length;
    const harness = navigation({selection: EditorSelection.create([
      EditorSelection.range(anchor, head, 140, 0, -1),
    ])});
    const measuredHead = forward ? block.from + 1 : block.to - 2;
    harness.view.posAtCoords.mockReturnValue(measuredHead);

    expect(harness.run(forward ? "Shift-ArrowDown" : "Shift-ArrowUp")).toBe(true);
    expect(harness.view.state.selection.main.anchor).toBe(anchor);
    await harness.measure();
    expect(harness.view.state.selection.main).toMatchObject({
      anchor, head: measuredHead, goalColumn: 140, bidiLevel: 0,
    });
    expect(harness.view.state.doc.toString()).toBe(source);
  });

  it.each([
    {forward: true, extend: false}, {forward: false, extend: false},
    {forward: true, extend: true}, {forward: false, extend: true},
  ])("retains the vertical goal when CodeMirror lands exactly at the incoming boundary ($forward, $extend)", async ({forward, extend}) => {
    const head = forward ? block.from - 1 : block.to + 1;
    const anchor = extend ? forward ? 0 : source.length : head;
    const harness = navigation({selection: EditorSelection.create([
      extend ? EditorSelection.range(anchor, head, 140) : EditorSelection.cursor(head, 0, undefined, 140),
    ])});
    const incomingHead = forward ? block.from : block.to;
    const measuredHead = forward ? block.from + 1 : block.to - 2;
    harness.view.moveVertically.mockReturnValue(EditorSelection.cursor(incomingHead));
    harness.view.posAtCoords.mockReturnValue(measuredHead);

    const key = `${extend ? "Shift-" : ""}${forward ? "ArrowDown" : "ArrowUp"}`;
    expect(harness.run(key)).toBe(true);
    await harness.measure();
    expect(harness.view.state.selection.main).toMatchObject({
      anchor: extend ? anchor : measuredHead, head: measuredHead,
      empty: !extend, goalColumn: 140,
    });
    expect(harness.view.posAtCoords).toHaveBeenCalledWith({x: 150, y: 30});
    expect(harness.view.state.doc.toString()).toBe(source);
  });

  it("uses CodeMirror's newly measured goal when the source cursor has no previous goal", async () => {
    const harness = navigation({selection: EditorSelection.single(5)});
    expect(harness.run("ArrowDown")).toBe(true);
    await harness.measure();
    expect(harness.view.state.selection.main.goalColumn).toBe(140);
    expect(harness.view.posAtCoords).toHaveBeenCalledWith({x: 150, y: 30});
  });

  it.each(["😀", "e\u0301", "🧑‍🔬", "中"])("enters a heading ending in %s at a complete source grapheme", async ending => {
    const heading = `# 中文${ending}`;
    const headingSource = `${heading}\n\nbelow`;
    const harness = navigation({doc: headingSource,
      selection: EditorSelection.single(headingSource.length),
      blocks: [{from: 0, to: heading.length, kind: "heading"}]});
    harness.view.moveVertically.mockReturnValue(EditorSelection.cursor(0, 1, 0, 140));
    const clusterStart = heading.length - ending.length;
    harness.view.posAtCoords.mockReturnValue(clusterStart);

    expect(harness.run("ArrowUp")).toBe(true);
    expect(harness.view.state.selection.main).toMatchObject({
      anchor: clusterStart, head: clusterStart, empty: true,
    });
    await harness.measure();
    expect(harness.view.state.selection.main.empty).toBe(true);
    expect(harness.view.state.doc.toString()).toBe(headingSource);
  });

  it.each(["document", "anchor", "mode", "composition"])("rejects stale projected-entry measurement after %s changes", async change => {
    const harness = navigation({selection: EditorSelection.single(5)});
    expect(harness.run("ArrowDown")).toBe(true);
    const measure = harness.pending.shift()!;
    const measured = measure.read();
    const sourceHead = harness.view.state.selection.main.head;
    if (change === "document") {
      harness.change({changes: {from: source.length, insert: " newer"}});
    } else if (change === "anchor") {
      harness.change({selection: {anchor: 0, head: sourceHead}});
    } else if (change === "mode") {
      harness.mode("source");
    } else {
      harness.view.composing = true;
    }
    const retained = harness.view.state;
    measure.write(measured);
    await Promise.resolve();
    expect(harness.view.state).toBe(retained);
    expect(harness.dispatch).toHaveBeenCalledTimes(1);
  });

  it("rejects changed source before reading any new projected geometry", async () => {
    const harness = navigation({selection: EditorSelection.single(5)});
    expect(harness.run("ArrowDown")).toBe(true);
    harness.change({changes: {from: source.length, insert: " newer"}});
    await harness.measure();
    expect(harness.view.posAtCoords).not.toHaveBeenCalled();
    expect(harness.dispatch).toHaveBeenCalledTimes(1);
  });

  it("retains pending entry when layout republishes the same selection value", async () => {
    const harness = navigation({selection: EditorSelection.single(5)});
    expect(harness.run("ArrowDown")).toBe(true);
    const selection = harness.view.state.selection.main;
    harness.change({selection: EditorSelection.create([
      EditorSelection.cursor(selection.head, selection.assoc,
        selection.bidiLevel ?? undefined, selection.goalColumn),
    ])});
    await harness.measure();
    expect(harness.view.state.selection.main.head).toBe(block.from + 1);
    expect(harness.view.state.selection.main.empty).toBe(true);
    expect(harness.view.state.selection.main.goalColumn).toBe(140);
  });

  it("commits selection after the measure write has returned", async () => {
    const harness = navigation({selection: EditorSelection.single(5)});
    expect(harness.run("ArrowDown")).toBe(true);
    const measure = harness.pending.shift()!;
    measure.write(measure.read());
    expect(harness.dispatch).toHaveBeenCalledTimes(1);
    await Promise.resolve();
    expect(harness.dispatch).toHaveBeenCalledTimes(2);
    expect(harness.view.state.selection.main.head).toBe(block.from + 1);
  });

  it.each(["document", "anchor", "mode", "composition"])("rejects input after the measure write but before the deferred commit (%s)", async change => {
    const harness = navigation({selection: EditorSelection.single(5)});
    expect(harness.run("ArrowDown")).toBe(true);
    const measure = harness.pending.shift()!;
    measure.write(measure.read());
    if (change === "document") harness.change({changes: {from: source.length, insert: " newer"}});
    else if (change === "anchor") harness.change({selection: {anchor: 0, head: block.from}});
    else if (change === "mode") harness.mode("source");
    else harness.view.composing = true;
    const retained = harness.view.state;
    await Promise.resolve();
    expect(harness.view.state).toBe(retained);
    expect(harness.dispatch).toHaveBeenCalledTimes(1);
  });

  it.each(["ArrowDown", "ArrowUp", "ArrowRight", "ArrowLeft"])("lets CodeMirror collapse existing selections for %s", key => {
    const linkSource = "text [[Target]]";
    const link = {from: 5, to: linkSource.length, kind: "wikilink"};
    const harness = navigation({doc: linkSource,
      selection: EditorSelection.single(0, link.from), blocks: [], links: [link]});
    expect(harness.run(key)).toBe(false);
    expect(harness.dispatch).not.toHaveBeenCalled();
    expect(harness.view.state.selection.main).toMatchObject({anchor: 0, head: link.from});
  });

  it.each(["ArrowDown", "Shift-ArrowDown", "ArrowRight", "Shift-ArrowRight"])("lets CodeMirror retain and move multiple selections for %s", key => {
    const harness = navigation({selection: EditorSelection.create([
      EditorSelection.cursor(2), EditorSelection.cursor(5),
    ], 1)});
    const retained = harness.view.state.selection;
    expect(harness.run(key)).toBe(false);
    expect(harness.view.state.selection).toBe(retained);
    expect(harness.view.state.selection.ranges).toHaveLength(2);
    expect(harness.dispatch).not.toHaveBeenCalled();
  });

  it("lets Shift-Right select one source character at an already active Wikilink boundary", () => {
    const linkSource = "text [[Target]]";
    const link = {from: 5, to: linkSource.length, kind: "wikilink"};
    const harness = navigation({doc: linkSource,
      selection: EditorSelection.single(link.from), blocks: [], links: [link]});
    expect(harness.run("Shift-ArrowRight")).toBe(false);
    expect(selectCharRight(harness.view as unknown as EditorView)).toBe(true);
    expect(harness.view.state.selection.main).toMatchObject({anchor: link.from, head: link.from + 1});
    expect(harness.view.state.sliceDoc(link.from, link.from + 1)).toBe("[");
  });

  it.each(["list", "heading"])("lets Shift-Right extend past an inactive %s's incoming edge", kind => {
    const boundarySource = kind === "list" ? "before\n- item" : "before\n# title";
    const from = boundarySource.indexOf("\n") + 1;
    const harness = navigation({doc: boundarySource,
      selection: EditorSelection.single(0, from),
      blocks: kind === "heading" ? [{from, to: boundarySource.length, kind}] : [],
      lists: kind === "list" ? [{from, to: from + 2}] : [],
    });
    expect(harness.run("Shift-ArrowRight")).toBe(false);
    expect(harness.dispatch).not.toHaveBeenCalled();
    expect(selectCharRight(harness.view as unknown as EditorView)).toBe(true);
    expect(harness.view.state.selection.main).toMatchObject({anchor: 0, head: from + 1});
    expect(harness.view.state.doc.toString()).toBe(boundarySource);
  });

  it("keeps CodeMirror's character movement and affinity while entering an active list prefix", () => {
    const listSource = "- [ ] 中文🧑‍🔬 e\u0301";
    const harness = navigation({doc: listSource,
      selection: EditorSelection.single(2), blocks: [], lists: [{from: 0, to: 6}]});
    const original = harness.view.state.selection.main;
    expect(harness.run("Shift-ArrowRight")).toBe(true);
    expect(harness.view.moveByChar).toHaveBeenCalledExactlyOnceWith(original, true);
    expect(harness.view.state.selection.main).toMatchObject({anchor: 2, head: 3, assoc: -1, bidiLevel: 0});
    expect(harness.view.state.doc.toString()).toBe(listSource);
  });
});

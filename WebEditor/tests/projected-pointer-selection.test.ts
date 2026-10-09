import {EditorSelection, EditorState, type Extension} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {describe, expect, it} from "vitest";
import {projectedPointerSelection} from "../projected-pointer-selection";

function pointerState(selection = EditorSelection.single(2), extensions: Extension[] = [], multiple = true) {
  return EditorState.create({doc: "01234567890123456789", selection,
    extensions: [EditorState.allowMultipleSelections.of(multiple), ...extensions]});
}

function pointer(event: Partial<MouseEvent> = {}): MouseEvent {
  return {detail: 1, shiftKey: false, metaKey: false, ...event} as MouseEvent;
}

describe("projected pointer modifier selection", () => {
  it("adds a primary caret on Command-click without discarding existing ranges", () => {
    const state = pointerState(EditorSelection.single(2, 4));
    const result = projectedPointerSelection(state, pointer({metaKey: true}), 10, -1);
    expect(result.ranges.map(range => [range.anchor, range.head])).toEqual([[2, 4], [10, 10]]);
    expect(result.main).toMatchObject({anchor: 10, head: 10, assoc: -1});
    expect(state.selection.main).toMatchObject({anchor: 2, head: 4});
  });

  it.each([false, true])("extends only the main range on Shift-click, retaining secondary ranges (Command: %s)", metaKey => {
    const state = pointerState(EditorSelection.create([
      EditorSelection.cursor(2), EditorSelection.range(10, 13),
    ], 1));
    const result = projectedPointerSelection(state, pointer({shiftKey: true, metaKey}), 17);
    expect(result.ranges.map(range => [range.anchor, range.head])).toEqual([[2, 2], [10, 17]]);
    expect(result.mainIndex).toBe(1);
  });

  it.each([2, 6, 10])("toggles an existing caret with Command-click at %s using the native main-index policy", head => {
    const state = pointerState(EditorSelection.create([
      EditorSelection.cursor(2), EditorSelection.cursor(6), EditorSelection.cursor(10),
    ], 1));
    const result = projectedPointerSelection(state, pointer({metaKey: true}), head);
    expect(result.ranges.map(range => range.head)).toEqual([2, 6, 10].filter(value => value !== head));
    expect(result.main.head).toBe(head === 6 ? 2 : 6);
  });

  it("removes a containing selection and keeps a sole remaining caret", () => {
    const state = pointerState(EditorSelection.create([
      EditorSelection.cursor(2), EditorSelection.range(6, 10),
    ], 1));
    const remaining = projectedPointerSelection(state, pointer({metaKey: true}), 8);
    expect(remaining.ranges).toHaveLength(1);
    expect(remaining.main.head).toBe(2);
    const single = projectedPointerSelection(pointerState(remaining), pointer({metaKey: true}), 2);
    expect(single.ranges).toHaveLength(1);
    expect(single.main.head).toBe(2);
  });

  it("honors the first clickAddsSelectionRange override instead of forcing Command", () => {
    const disabled = pointerState(undefined, [
      EditorView.clickAddsSelectionRange.of(() => false),
      EditorView.clickAddsSelectionRange.of(() => true),
    ]);
    expect(projectedPointerSelection(disabled, pointer({metaKey: true}), 10).ranges).toHaveLength(1);
    const custom = pointerState(undefined, [EditorView.clickAddsSelectionRange.of(event => event.altKey)]);
    expect(projectedPointerSelection(custom, pointer({altKey: true}), 10).ranges).toHaveLength(2);
    expect(projectedPointerSelection(custom, pointer({metaKey: true}), 10).ranges).toHaveLength(1);
  });

  it("respects disabled multiple selection and ordinary click replacement", () => {
    const single = pointerState(undefined, [EditorView.clickAddsSelectionRange.of(() => true)], false);
    expect(projectedPointerSelection(single, pointer({metaKey: true}), 10).ranges).toHaveLength(1);
    const state = pointerState(EditorSelection.create([EditorSelection.cursor(2), EditorSelection.cursor(6)]));
    expect(projectedPointerSelection(state, pointer(), 10).ranges).toHaveLength(1);
    expect(projectedPointerSelection(state, pointer(), 10).main.head).toBe(10);
  });
});

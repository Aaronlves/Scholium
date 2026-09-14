import {EditorSelection} from "@codemirror/state";
import {describe, expect, it} from "vitest";
import {selectionForContextClick, selectionForParagraphContext} from "../context-menu";

describe("editor context-menu selection", () => {
  it("preserves a passage when secondary click lands inside it", () => {
    const selected = EditorSelection.single(4, 12);
    expect(selectionForContextClick(selected, 8).eq(selected)).toBe(true);
  });

  it("moves the authoritative caret before evaluating an outside click", () => {
    const selected = EditorSelection.single(4, 12);
    const result = selectionForContextClick(selected, 18);
    expect(result.main.anchor).toBe(18);
    expect(result.main.head).toBe(18);
  });

  it("treats the exclusive selection end as outside the selected passage", () => {
    const selected = EditorSelection.single(4, 12);
    expect(selectionForContextClick(selected, 12).main.empty).toBe(true);
  });

  it("preserves multiple ranges when the click belongs to any one of them", () => {
    const selected = EditorSelection.create([
      EditorSelection.range(2, 5),
      EditorSelection.range(10, 14),
    ], 1);
    expect(selectionForContextClick(selected, 11).eq(selected)).toBe(true);
  });
});


describe("paragraph context target", () => {
  it("shows the complete clicked ordinary paragraph when there is no selected text", () => {
    const result = selectionForParagraphContext(EditorSelection.single(6), 8, {from: 4, to: 12});
    expect([result.main.from, result.main.to]).toEqual([4, 12]);
  });
  it("does not expand an existing partial selection", () => {
    const selected = EditorSelection.single(5, 8);
    expect(selectionForParagraphContext(selected, 6, {from: 4, to: 12}).eq(selected)).toBe(true);
  });
  it("leaves a protected object at its clicked caret", () => {
    const result = selectionForParagraphContext(EditorSelection.single(1), 8, null);
    expect(result.main.empty).toBe(true);
    expect(result.main.head).toBe(8);
  });
});

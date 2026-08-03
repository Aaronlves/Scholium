import {EditorSelection} from "@codemirror/state";
import {describe, expect, it} from "vitest";
import {selectionForContextClick} from "../context-menu";

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

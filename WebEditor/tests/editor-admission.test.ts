import {EditorSelection, EditorState} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {history, undo, undoDepth, redo} from "@codemirror/commands";
import {describe, expect, it} from "vitest";
import {createMarkdownDocumentState} from "../bootstrap";
import {captureExactHistory, exactSourceFitsChanges, exactSourceHistory, exactSourceState, restoreExactHistory, setExactSource, sourceCapacityExceeded} from "../exact-source-history";
import {editorSuspension, editorSuspensionState, setEditorSuspension, titleAllowsDetachment} from "../editor-suspension";
import {ExactSourceMirror} from "../state";

const extensions = [history(), exactSourceHistory, editorSuspension, EditorState.lineSeparator.of("\n")];
const initial = (source: string) => createMarkdownDocumentState(source, extensions);

function perform(state: EditorState, command: typeof undo) {
  command({state, dispatch: transaction => { state = transaction.state; }});
  return state;
}

describe("exact source transaction admission", () => {
  it("refuses direct typing beyond the exact limit without moving selection or history", () => {
    const source = "x\r\n" + "a".repeat(7_999_997);
    const state = initial(source);
    const transaction = state.update({changes: {from: 1, insert: "界"}, selection: {anchor: 2}, userEvent: "input.type"});
    expect(transaction.docChanged).toBe(false);
    expect(transaction.state.selection.eq(state.selection)).toBe(true);
    expect(transaction.effects.some(effect => effect.is(sourceCapacityExceeded))).toBe(true);
    expect(transaction.state.field(exactSourceState).text).toBe(source);
    expect(undoDepth(transaction.state)).toBe(0);
    const shortened = transaction.state.update({changes: {from: 3, to: 6}, userEvent: "delete.backward"}).state;
    expect(shortened.field(exactSourceState).utf8ByteCount).toBe(7_999_997);
    const restored = perform(shortened, undo);
    expect(restored.field(exactSourceState).text).toBe(source);
    expect(perform(restored, redo).field(exactSourceState).text).toBe(shortened.field(exactSourceState).text);
  });

  it("rejects oversized initialization, exact-source replacement and recovery", () => {
    const oversized = "a".repeat(8_000_001);
    expect(() => initial(oversized)).toThrow("editor size");
    const state = initial("safe");
    const attempted = state.update({changes: {from: 0, to: 4, insert: oversized}, effects: setExactSource.of(oversized)}).state;
    expect(attempted.field(exactSourceState).text).toBe("safe");
    expect(() => restoreExactHistory(captureExactHistory(state)!, oversized, extensions)).toThrow("editor size");
    expect(() => state.update({changes: {from: 4, insert: oversized}, filter: false}).state).toThrow("editor size");
  });

  it("counts mixed newline and surrogate-boundary changes exactly", () => {
    let mirror = new ExactSourceMirror("\uFEFFa\r\n😀é\nb");
    for (const changes of [
      [{from: 4, to: 4, insert: "x"}],
      [{from: 4, to: 5, insert: ""}],
      [{from: 0, to: 1, insert: "界"}, {from: 8, to: 9, insert: "\n"}],
    ]) {
      const next = mirror.copy();
      expect(next.apply(changes)).toBe(true);
      expect(next.utf8ByteCount).toBe(new TextEncoder().encode(next.text).byteLength);
      mirror = next;
    }
  });

  it("preflights multi-range growth without constructing an oversized result", () => {
    const state = initial("x\r\nx");
    expect(exactSourceFitsChanges(state, [
      {from: 0, to: 1, insert: "a".repeat(4_000_000)},
      {from: 2, to: 3, insert: "b".repeat(4_000_000)},
    ])).toBe(false);
  });
});

describe("detachment capture state", () => {
  it("does not detach a live filename draft or an unresolved rename", () => {
    expect(titleAllowsDetachment("Title", "Draft", false)).toBe(false);
    expect(titleAllowsDetachment("Title", "", false)).toBe(false);
    expect(titleAllowsDetachment("Title", null, true)).toBe(false);
    expect(titleAllowsDetachment("Title", "Title", false)).toBe(true);
    expect(titleAllowsDetachment("Title", null, false)).toBe(true);
  });
  it("freezes input and retains source/history while the captured state restores writable", () => {
    let state = initial("a\r\nb\nc");
    state = state.update({changes: {from: 1, to: 2}, selection: EditorSelection.single(1), userEvent: "delete.forward"}).state;
    const source = state.field(exactSourceState).text;
    const frozen = state.update({effects: setEditorSuspension.of("capture")}).state;
    expect(frozen.readOnly).toBe(true);
    expect(frozen.facet(EditorView.editable)).toBe(false);
    expect(frozen.update({changes: {from: 0, insert: "late"}, selection: {anchor: 4}}).state.doc.toString()).toBe(state.doc.toString());
    expect(() => frozen.update({changes: {from: 0, insert: "late"}, filter: false}).state).toThrow("suspended");
    const captureState = frozen.update({effects: setEditorSuspension.of(null)}).state;
    const restored = restoreExactHistory(captureExactHistory(captureState)!, source, extensions);
    expect(frozen.field(editorSuspensionState)).toBe("capture");
    const superseded = frozen.update({effects: setEditorSuspension.of("new-capture")}).state;
    expect(superseded.field(editorSuspensionState)).toBe("new-capture");
    expect(superseded.readOnly).toBe(true);
    expect(restored.field(editorSuspensionState)).toBeNull();
    expect(restored.readOnly).toBe(false);
    expect(perform(restored, undo).field(exactSourceState).text).toBe("a\r\nb\nc");
    expect(initial("another").field(editorSuspensionState)).toBeNull();
  });
});

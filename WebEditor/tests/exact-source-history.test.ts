import {EditorSelection, EditorState, Transaction} from "@codemirror/state";
import {history, isolateHistory, redo, redoDepth, undo, undoDepth, undoSelection} from "@codemirror/commands";
import {describe, expect, it} from "vitest";
import {captureExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {continueList} from "../interaction";

const extensions = [history(), exactSourceHistory, EditorState.lineSeparator.of("\n")];
function initial(source: string) {
  return EditorState.create({doc: normalizedDocumentText(source), extensions})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
}
const exact = (state: EditorState) => state.field(exactSourceState).text;
function perform(state: EditorState, command: typeof undo) {
  let next = state;
  expect(command({state, dispatch: transaction => { next = transaction.state; }})).toBe(true);
  return next;
}

describe("exact newline history", () => {
  it("maps inverse newline positions across nonhistory text changes", () => {
    let state = initial("a\r\nb\nc");
    state = state.update({changes: {from: 0, to: 5, insert: ""}}).state;
    state = state.update({changes: {from: 0, insert: "x"}, annotations: Transaction.addToHistory.of(false)}).state;
    state = perform(state, undo);
    expect(exact(state)).toBe("xa\r\nb\nc");
  });

  it("retains exact grouped history through several lazy nonhistory mappings", () => {
    let state = initial("a\r\nb\nc\r\nd\ne");
    const edits = [
      {from: 0, to: 3, insert: "x\ny", recorded: false},
      {from: 3, to: 8, insert: "", recorded: true},
      {from: 0, to: 4, insert: "x", recorded: true},
      {from: 1, to: 1, insert: "\n", recorded: false},
      {from: 1, to: 2, insert: "x\ny", recorded: true},
      {from: 0, to: 4, insert: "", recorded: true},
    ];
    for (const change of edits) state = state.update({changes: change,
      annotations: [Transaction.addToHistory.of(change.recorded), isolateHistory.of("full")]}).state;
    const serialized = captureExactHistory(state);
    expect(serialized).toBeDefined();
    const recovered = restoreExactHistory(serialized!, exact(state), extensions);
    for (const command of [undo, redo]) {
      let originalBranch = state, recoveredBranch = recovered;
      while ((command === undo ? undoDepth(originalBranch) : redoDepth(originalBranch)) > 0) {
        originalBranch = perform(originalBranch, command);
        recoveredBranch = perform(recoveredBranch, command);
        expect(exact(recoveredBranch)).toBe(exact(originalBranch));
      }
    }
  });

  it("preserves selection-only Undo events during recovery", () => {
    let state = initial("a\r\nb\nc");
    state = state.update({changes: {from: 0, insert: "x"}, selection: {anchor: 1},
      annotations: isolateHistory.of("full")}).state;
    state = state.update({selection: {anchor: 3}, userEvent: "select.pointer",
      annotations: Transaction.time.of(1000)}).state;
    state = state.update({selection: {anchor: 5}, userEvent: "select.pointer",
      annotations: Transaction.time.of(2000)}).state;
    const restored = restoreExactHistory(captureExactHistory(state)!, exact(state), extensions);
    expect(restored.selection.eq(state.selection)).toBe(true);
    const originalUndo = perform(state, undoSelection);
    const recoveredUndo = perform(restored, undoSelection);
    expect(exact(recoveredUndo)).toBe(exact(state));
    expect(recoveredUndo.selection.eq(originalUndo.selection)).toBe(true);
  });
  it.each(["one\r\ntwo", "one\r\ntwo\nthree\r\n", "\uFEFFone\r\ntwo\nthree\rfour"])(
    "restores exact deleted newline bytes with Undo and Redo: %s", source => {
      let state = initial(source);
      const from = source.includes("three") ? state.doc.toString().indexOf("two") + 3 : 3;
      state = state.update({changes: {from, to: from + 1}, annotations: isolateHistory.of("full")}).state;
      const deleted = exact(state);
      state = perform(state, undo);
      expect(exact(state)).toBe(source);
      expect(state.doc.toString()).toBe(normalizedDocumentText(source));
      state = perform(state, redo);
      expect(exact(state)).toBe(deleted);
    });

  it("restores mixed newlines inside one grouped deletion and redo", () => {
    const source = "a\r\nb\nc\r\nd";
    let state = initial(source);
    for (let index = 0; index < 5; index++) {
      state = state.update({changes: {from: 1, to: 2}, userEvent: "delete.forward"}).state;
    }
    expect(undoDepth(state)).toBe(1);
    const edited = exact(state);
    state = perform(state, undo);
    expect(exact(state)).toBe(source);
    state = perform(state, redo);
    expect(exact(state)).toBe(edited);
  });

  it("keeps CodeMirror logical lines normalized when continuing a CRLF list", () => {
    let state = initial("- one\r\n- two");
    const change = continueList(state.doc, [{anchor: 5, head: 5}])!;
    state = state.update({changes: change.changes,
      selection: EditorSelection.create(change.selections.map(range => EditorSelection.range(range.anchor, range.head)))}).state;
    expect(state.doc.lines).toBe(3);
    expect(state.doc.line(1).text).toBe("- one");
    expect(state.doc.line(2).text).toBe("- ");
    expect(exact(state)).toBe("- one\r\n- \r\n- two");
  });

  it("recovers both Undo and Redo branches with exact mixed newline metadata", () => {
    const source = "a\r\nb\nc\r\nd";
    let state = initial(source);
    state = state.update({changes: {from: 3, to: 4}, annotations: isolateHistory.of("full")}).state;
    const first = exact(state);
    state = state.update({changes: {from: 1, to: 2}, annotations: isolateHistory.of("full")}).state;
    const second = exact(state);
    state = perform(state, undo);
    const serialized = captureExactHistory(state);
    expect(serialized).toBeDefined();
    const recovered = restoreExactHistory(serialized!, first, extensions);
    expect(exact(recovered)).toBe(first);
    expect(undoDepth(recovered)).toBe(undoDepth(state));
    expect(redoDepth(recovered)).toBe(redoDepth(state));
    expect(exact(perform(recovered, undo))).toBe(source);
    expect(exact(perform(recovered, redo))).toBe(second);
  });

  it("recovers grouped deletion history and multi-selection changes without merging events", () => {
    const source = "a\r\nb\nc\r\nd";
    let state = initial(source);
    state = state.update({changes: [{from: 1, to: 2}, {from: 5, to: 6}], annotations: isolateHistory.of("full")}).state;
    const first = exact(state);
    state = state.update({changes: {from: 1, to: 3}, userEvent: "delete.forward"}).state;
    state = state.update({changes: {from: 1, to: 2}, userEvent: "delete.forward"}).state;
    const recovered = restoreExactHistory(captureExactHistory(state)!, exact(state), extensions);
    expect(undoDepth(recovered)).toBe(2);
    const beforeGroup = perform(recovered, undo);
    expect(exact(beforeGroup)).toBe(first);
    expect(exact(perform(beforeGroup, undo))).toBe(source);
  });

  it("rejects recovery metadata that does not match the history document", () => {
    let state = initial("a\r\nb");
    state = state.update({changes: {from: 1, to: 2}}).state;
    const payload = JSON.parse(captureExactHistory(state)!);
    payload.undoLineEndings = [""];
    expect(() => restoreExactHistory(JSON.stringify(payload), exact(state), extensions)).toThrow();
  });
});

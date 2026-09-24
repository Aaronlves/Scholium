import {EditorSelection, EditorState, Transaction} from "@codemirror/state";
import {history, redo, undo} from "@codemirror/commands";
import {describe, expect, it} from "vitest";
import {transformMarkdown} from "../transformations";

describe("CodeMirror transaction and history integration", () => {
  it("applies a multi-selection command as one undoable transaction", () => {
    const original = "one two three";
    let state = EditorState.create({doc: original, extensions: [history()]});
    const transformed = transformMarkdown(original, [
      {anchor: 0, head: 3},
      {anchor: 8, head: 13},
    ], "bold")!;
    state = state.update({
      changes: transformed.changes,
      selection: EditorSelection.create(
        transformed.selections.map((range) => EditorSelection.range(range.anchor, range.head)),
      ),
      annotations: Transaction.userEvent.of("input.scholium.bold"),
    }).state;
    expect(state.doc.toString()).toBe("**one** two **three**");

    const target = {state, dispatch: (transaction: Transaction) => { state = transaction.state; }};
    expect(undo(target)).toBe(true);
    expect(state.doc.toString()).toBe(original);
    expect(redo({state, dispatch: target.dispatch})).toBe(true);
    expect(state.doc.toString()).toBe("**one** two **three**");
  });
});

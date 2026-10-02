import {EditorState, Transaction} from "@codemirror/state";
import {history, isolateHistory, redo, undo, undoDepth} from "@codemirror/commands";
import {describe, expect, it} from "vitest";
import {sourcePatch} from "../source-patch";
import {exactInsertionEffects, exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {EDITOR_PROTOCOL_VERSION, generationCanExecuteEditorRequest, isEditorRequest} from "../protocol";

describe("native exact-source metadata patches", () => {
  it("preserves exact mixed newline insertion, source selection, and one-step Undo/Redo", () => {
    const source = "\uFEFF---\r\nsummary: old\nunknown: keep\r\n---\nBody 😀\r\n";
    let state = EditorState.create({doc: normalizedDocumentText(source), selection: {anchor: normalizedDocumentText(source).indexOf("Body")},
      extensions: [history(), exactSourceHistory, EditorState.lineSeparator.of("\n")]})
      .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
    const from = source.indexOf("old"), to = source.indexOf("---\nBody");
    const insertion = "'new'\nunknown: keep\r\npdf: '../.scholium/Paper.pdf'\n";
    const patch = sourcePatch(source, source, from, to, insertion)!;
    state = state.update({changes: patch, effects: exactInsertionEffects(patch.exactInsert, patch.from),
      annotations: [Transaction.userEvent.of("input.scholium.noteInfo"), isolateHistory.of("full")]}).state;
    const after = source.slice(0, from) + insertion + source.slice(to);
    expect(state.field(exactSourceState).text).toBe(after);
    expect(state.doc.sliceString(state.selection.main.head, state.selection.main.head + 4)).toBe("Body");
    expect(undoDepth(state)).toBe(1);
    expect(undo({state, dispatch: transaction => { state = transaction.state; }})).toBe(true);
    expect(state.field(exactSourceState).text).toBe(source);
    expect(redo({state, dispatch: transaction => { state = transaction.state; }})).toBe(true);
    expect(state.field(exactSourceState).text).toBe(after);
  });

  it("allows detach deletion but refuses stale bytes and split scalar/newline boundaries", () => {
    expect(sourcePatch("pdf: a\nBody", "pdf: a\nBody", 0, 7, "")?.insert).toBe("");
    expect(sourcePatch("changed", "original", 0, 4, "x")).toBeNull();
    expect(sourcePatch("a\r\nb", "a\r\nb", 2, 3, "x")).toBeNull();
    expect(sourcePatch("😀", "😀", 1, 2, "x")).toBeNull();
    expect(sourcePatch("\uFEFFBody", "\uFEFFBody", 0, 1, "")).toBeNull();
  });

  it("requires the exact generation and a bounded structured source envelope", () => {
    const request = {protocolVersion: EDITOR_PROTOCOL_VERSION, requestID: "id", sessionID: "session", documentID: "note", startingFingerprint: "fp",
      knownGeneration: 2, expiresAt: Date.now() + 1000,
      operation: {type: "applySourcePatch", expectedText: "pdf: a\n", fromUTF16: 0, toUTF16: 7, replacement: ""}};
    expect(isEditorRequest(request)).toBe(true);
    expect(isEditorRequest({...request, operation: {...request.operation, toUTF16: 8}})).toBe(false);
    expect(generationCanExecuteEditorRequest("applySourcePatch", 2, 3)).toBe(false);
    expect(generationCanExecuteEditorRequest("applySourcePatch", 3, 3)).toBe(true);
  });
});

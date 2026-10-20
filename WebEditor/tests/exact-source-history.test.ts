import {EditorSelection, EditorState, StateEffect, StateField, Transaction} from "@codemirror/state";
import {history, historyField, invertedEffects, isolateHistory, redo, redoDepth, redoSelection, undo, undoDepth, undoSelection} from "@codemirror/commands";
import {describe, expect, it} from "vitest";
import {captureExactHistory, hasExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {continueList} from "../interaction";
import {MAX_SOURCE_UTF8_BYTES} from "../source-capacity";
import {MAX_INBOUND_BYTES, MAX_RECOVERY_HISTORY_BYTES} from "../protocol";

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
  it("distinguishes empty, selection-only, edited and redo-only retained histories", () => {
    const empty = initial("abc");
    expect(hasExactHistory(empty)).toBe(false);
    const selected = empty.update({selection: {anchor: 2}, annotations: Transaction.userEvent.of("select")}).state;
    expect(undoDepth(selected)).toBe(0);
    expect(hasExactHistory(selected)).toBe(true);
    const edited = empty.update({changes: {from: 0, insert: "x"}}).state;
    expect(hasExactHistory(edited)).toBe(true);
    const undone = perform(edited, undo);
    expect(undoDepth(undone)).toBe(0);
    expect(redoDepth(undone)).toBe(1);
    expect(hasExactHistory(undone)).toBe(true);
  });
  it("retains a full supported-size replacement through document reconstruction", () => {
    const source = "a".repeat(MAX_SOURCE_UTF8_BYTES - 4) + "\r\n\r\n";
    const replacement = "b".repeat(MAX_SOURCE_UTF8_BYTES - 4) + "\r\n\r\n";
    const state = initial(source).update({changes: {from: 0, to: normalizedDocumentText(source).length,
      insert: normalizedDocumentText(replacement)}}).state;
    const serialized = captureExactHistory(state);
    expect(serialized).toBeDefined();
    expect(new TextEncoder().encode(serialized!).byteLength).toBeGreaterThan(MAX_INBOUND_BYTES);
    const recovered = restoreExactHistory(serialized!, replacement, extensions);
    expect(undoDepth(recovered)).toBe(1);
    expect(exact(perform(recovered, undo))).toBe(source);
    expect(exact(perform(perform(recovered, undo), redo))).toBe(replacement);
  });

  it("stores separators only for changed history material in a line-rich document", () => {
    const source = "a\r\nb\n".repeat(90_000);
    let state = initial(source);
    for (let index = 0; index < 60; index++) {
      state = state.update({changes: {from: 0, insert: "x"}, annotations: isolateHistory.of("full")}).state;
    }
    const serialized = captureExactHistory(state)!;
    expect(serialized).toBeDefined();
    expect(JSON.parse(serialized).effects.done).toEqual(Array.from({length: 60}, () => []));
    expect(new TextEncoder().encode(serialized).byteLength)
      .toBeLessThan(new TextEncoder().encode(JSON.stringify(state.doc.toString())).byteLength + 20_000);
    const recovered = restoreExactHistory(serialized, exact(state), extensions);
    expect(undoDepth(recovered)).toBe(60);
    let undone = recovered;
    for (let index = 0; index < 60; index++) undone = perform(undone, undo);
    expect(exact(undone)).toBe(source);
  });

  it("accounts for escaped control text independently of the small message budget", () => {
    const source = "\u0000\"\\".repeat(150_000);
    const replacement = "\u0001\\\"".repeat(150_000);
    const state = initial(source).update({changes: {from: 0, to: source.length, insert: replacement}}).state;
    const serialized = captureExactHistory(state)!;
    expect(serialized).toBeDefined();
    expect(new TextEncoder().encode(serialized).byteLength).toBeGreaterThan(MAX_INBOUND_BYTES);
    expect(new TextEncoder().encode(serialized).byteLength).toBeLessThan(MAX_RECOVERY_HISTORY_BYTES);
    const recovered = restoreExactHistory(serialized, replacement, extensions);
    expect(exact(perform(recovered, undo))).toBe(source);
    expect(exact(perform(perform(recovered, undo), redo))).toBe(replacement);
  });

  it("recovers both branches of long selection history without an arbitrary step limit", () => {
    let state = initial("ab");
    for (let group = 0; group < 6; group++) {
      state = state.update({changes: {from: 0, insert: "x"}, annotations: isolateHistory.of("full")}).state;
      for (let selection = 0; selection < 190; selection++) {
        state = state.update({selection: {anchor: selection % 2}, userEvent: "select.pointer",
          annotations: Transaction.time.of((group * 190 + selection + 1) * 1000)}).state;
      }
    }
    for (let index = 0; index < 575; index++) state = perform(state, undoSelection);
    const serialized = captureExactHistory(state)!;
    expect(serialized).toBeDefined();
    const payload = JSON.parse(serialized);
    const selections = (branch: {selectionsAfter: unknown[]}[]) => branch.reduce((count, event) => count + event.selectionsAfter.length, 0);
    expect(selections(payload.state.history.done)).toBeGreaterThan(512);
    expect(selections(payload.state.history.undone)).toBeGreaterThan(512);
    const recovered = restoreExactHistory(serialized, exact(state), extensions);
    expect(recovered.selection.eq(state.selection)).toBe(true);
    expect(undoDepth(recovered)).toBe(undoDepth(state));
    expect(redoDepth(recovered)).toBe(redoDepth(state));
    expect(recovered.toJSON({history: historyField})).toEqual(state.toJSON({history: historyField}));
    for (const command of [undo, redo, undoSelection, redoSelection]) {
      let originalBranch = state, recoveredBranch = recovered;
      while (command({state: originalBranch, dispatch: transaction => { originalBranch = transaction.state; }})) {
        recoveredBranch = perform(recoveredBranch, command);
        expect(exact(recoveredBranch)).toBe(exact(originalBranch));
        expect(recoveredBranch.selection.eq(originalBranch.selection)).toBe(true);
      }
      expect(command({state: recoveredBranch, dispatch: () => {}})).toBe(false);
    }
  });

  it("rejects source and selection metadata that exceed an explicit serialization byte budget", () => {
    let state = initial("ab");
    state = state.update({changes: {from: 0, insert: "x"}, annotations: isolateHistory.of("full")}).state;
    for (let selection = 0; selection < 190; selection++) {
      state = state.update({selection: {anchor: selection % 2}, userEvent: "select.pointer",
        annotations: Transaction.time.of((selection + 1) * 1000)}).state;
    }
    expect(captureExactHistory(state)).toBeDefined();
    expect(captureExactHistory(state, 1_000)).toBeUndefined();
    expect(captureExactHistory(state, MAX_RECOVERY_HISTORY_BYTES + 1)).toBeUndefined();
    expect(undoDepth(state)).toBe(1);
    expect(exact(perform(state, undo))).toBe("ab");
  });

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

  it("preserves adjacent typing grouping across reconstruction", () => {
    const state = initial("ab").update({changes: {from: 0, insert: "1"}, userEvent: "input.type",
      annotations: Transaction.time.of(1000)}).state;
    const restored = restoreExactHistory(captureExactHistory(state)!, exact(state), extensions);
    const type = (value: EditorState) => value.update({changes: {from: 1, insert: "2"}, userEvent: "input.type",
      annotations: Transaction.time.of(1100)}).state;
    const oracle = type(state), recovered = type(restored);
    expect(undoDepth(oracle)).toBe(1);
    expect(undoDepth(recovered)).toBe(undoDepth(oracle));
    expect(recovered.toJSON({history: historyField})).toEqual(oracle.toJSON({history: historyField}));
    expect(exact(perform(recovered, undo))).toBe(exact(perform(oracle, undo)));
  });

  it("preserves selection grouping time and event type across reconstruction", () => {
    const state = initial("abcd").update({selection: {anchor: 1}, userEvent: "select.pointer",
      annotations: Transaction.time.of(1000)}).state;
    for (const userEvent of ["select.pointer", "select.keyboard"]) {
      const restored = restoreExactHistory(captureExactHistory(state)!, exact(state), extensions);
      const select = (value: EditorState) => value.update({selection: {anchor: 2}, userEvent,
        annotations: Transaction.time.of(1100)}).state;
      const oracle = select(state), recovered = select(restored);
      expect(recovered.toJSON({history: historyField})).toEqual(oracle.toJSON({history: historyField}));
      expect(perform(recovered, undoSelection).selection.eq(perform(oracle, undoSelection).selection)).toBe(true);
    }
  });

  it("retains complete multiple-selection JSON together with BOM and bare CR text", () => {
    const custom = [extensions, EditorState.allowMultipleSelections.of(true)];
    let state = EditorState.create({doc: "\uFEFFa\rb\nc", extensions: custom})
      .update({effects: setExactSource.of("\uFEFFa\rb\nc"), annotations: Transaction.addToHistory.of(false)}).state;
    state = state.update({selection: EditorSelection.create([EditorSelection.range(1, 3), EditorSelection.cursor(5)], 1),
      userEvent: "select.pointer"}).state;
    state = state.update({changes: [{from: 1, to: 3}, {from: 5, insert: "x"}], annotations: isolateHistory.of("full")}).state;
    const restored = restoreExactHistory(captureExactHistory(state)!, exact(state), custom);
    expect(restored.toJSON({history: historyField})).toEqual(state.toJSON({history: historyField}));
    const before = perform(state, undoSelection), recoveredBefore = perform(restored, undoSelection);
    expect(exact(recoveredBefore)).toBe(exact(before));
    expect(recoveredBefore.selection.eq(before.selection)).toBe(true);
  });

  it("constructs incoming derived fields once after decoding exact multi-selection history", () => {
    let derivedInitializations = 0;
    const derived = StateField.define({create: () => { derivedInitializations++; return null; }, update: value => value});
    const custom = [extensions, EditorState.allowMultipleSelections.of(true), derived];
    const source = "\uFEFFa\r\nCafe\u0301 中文 🦉\nTail\rEnd\r\nLast";
    let state = EditorState.create({doc: normalizedDocumentText(source), extensions: custom,
      selection: EditorSelection.create([EditorSelection.range(1, 2), EditorSelection.cursor(5)], 1),
    }).update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
    const newline = state.doc.toString().indexOf("\n");
    state = state.update({changes: {from: newline, to: newline + 1},
      annotations: isolateHistory.of("full")}).state;
    state = state.update({changes: {from: state.doc.length, insert: " Ω\n"},
      annotations: isolateHistory.of("full")}).state;
    state = perform(state, undo);
    state = state.update({selection: EditorSelection.create([EditorSelection.range(1, 2), EditorSelection.cursor(6)], 1),
      userEvent: "select.pointer", annotations: Transaction.time.of(1000)}).state;
    expect(state.selection.mainIndex).toBe(1);
    expect(undoDepth(state)).toBe(1);
    expect(redoDepth(state)).toBe(1);
    const serialized = captureExactHistory(state)!;
    expect(serialized).toBeDefined();
    const before = state.toJSON({history: historyField});
    derivedInitializations = 0;

    const recovered = restoreExactHistory(serialized, exact(state), custom);
    expect(derivedInitializations).toBe(1);
    expect(exact(recovered)).toBe(exact(state));
    expect(recovered.selection.mainIndex).toBe(1);
    expect(recovered.toJSON({history: historyField})).toEqual(before);
    for (const command of [undo, redo, undoSelection, redoSelection]) {
      let originalBranch = state, recoveredBranch = recovered;
      while (command({state: originalBranch, dispatch: transaction => { originalBranch = transaction.state; }})) {
        recoveredBranch = perform(recoveredBranch, command);
        expect(exact(recoveredBranch)).toBe(exact(originalBranch));
        expect(recoveredBranch.selection.eq(originalBranch.selection)).toBe(true);
      }
      expect(command({state: recoveredBranch, dispatch: () => {}})).toBe(false);
    }
    expect(exact(perform(recovered, undo))).toBe(source);
    const continueSelection = (value: EditorState) => value.update({
      selection: EditorSelection.create([EditorSelection.range(1, 2), EditorSelection.cursor(7)], 1),
      userEvent: "select.pointer", annotations: Transaction.time.of(1100),
    }).state;
    const groupedOriginal = continueSelection(state), groupedRecovered = continueSelection(recovered);
    expect(groupedRecovered.toJSON({history: historyField})).toEqual(groupedOriginal.toJSON({history: historyField}));
    expect(perform(groupedRecovered, undoSelection).selection.eq(perform(groupedOriginal, undoSelection).selection)).toBe(true);

    derivedInitializations = 0;
    expect(() => restoreExactHistory(serialized, exact(state) + "foreign source", custom)).toThrow();
    expect(derivedInitializations).toBe(0);
    const corrupted = JSON.parse(serialized);
    corrupted.effects.done[0] = [{unknown: 1}];
    expect(() => restoreExactHistory(JSON.stringify(corrupted), exact(state), custom)).toThrow();
    expect(derivedInitializations).toBe(0);
    expect(state.toJSON({history: historyField})).toEqual(before);
  });

  it("rejects unknown inverse effects before detaching the unchanged live state", () => {
    const unknown = StateEffect.define<string>();
    const custom = [extensions, invertedEffects.of(transaction => transaction.docChanged ? [unknown.of("unowned")] : [])];
    const state = EditorState.create({doc: "ab", extensions: custom})
      .update({changes: {from: 0, insert: "x"}}).state;
    const before = state.toJSON({history: historyField});
    expect(captureExactHistory(state)).toBeUndefined();
    expect(state.toJSON({history: historyField})).toEqual(before);
    expect(exact(state)).toBe("xab");
    expect(exact(perform(state, undo))).toBe("ab");
  });

  it("rejects malformed effect and lazy mapping metadata without changing the live source", () => {
    const state = initial("a\r\nb\nc").update({changes: {from: 1, to: 4}}).state;
    const serialized = captureExactHistory(state)!;
    const before = state.toJSON({history: historyField});
    for (const corrupt of [
      (payload: any) => { payload.effects.done = []; },
      (payload: any) => { payload.effects.done[0] = [{unknown: 1}]; },
      (payload: any) => { payload.effects.done[0][0].lineEndings[0][0] = -1; },
      (payload: any) => { payload.state.history.done[0].mapped = [-1, -1]; },
      (payload: any) => { delete payload.grouping; },
      (payload: any) => { payload.grouping.time = "1000"; },
      (payload: any) => { payload.grouping.userEvent = 1; },
    ]) {
      const payload = JSON.parse(serialized);
      corrupt(payload);
      expect(() => restoreExactHistory(JSON.stringify(payload), exact(state), extensions)).toThrow();
      expect(state.toJSON({history: historyField})).toEqual(before);
      expect(exact(state)).toBe("ac");
    }
  });

  it("retains ordinary grouping after recovery and maps both branches after nonhistory edits", () => {
    let state = initial("a\r\nb\nc");
    state = state.update({changes: {from: 1, to: 2}, annotations: isolateHistory.of("full")}).state;
    state = state.update({changes: {from: 2, to: 3}, annotations: isolateHistory.of("full")}).state;
    state = perform(state, undo);
    const recovered = restoreExactHistory(captureExactHistory(state)!, exact(state), extensions);
    const map = (value: EditorState) => value.update({changes: {from: 0, insert: "z"},
      annotations: Transaction.addToHistory.of(false)}).state;
    const mappedOriginal = map(state), mappedRecovered = map(recovered);
    for (const command of [undo, redo, undoSelection, redoSelection]) {
      let left = mappedOriginal, right = mappedRecovered;
      while (command({state: left, dispatch: transaction => { left = transaction.state; }})) {
        right = perform(right, command);
        expect(exact(right)).toBe(exact(left));
        expect(right.selection.eq(left.selection)).toBe(true);
      }
      expect(command({state: right, dispatch: () => {}})).toBe(false);
    }
    const typed = recovered.update({changes: {from: 0, insert: "1"}, userEvent: "input.type",
      annotations: Transaction.time.of(5000)}).state.update({changes: {from: 1, insert: "2"}, userEvent: "input.type",
        annotations: Transaction.time.of(5100)}).state;
    expect(undoDepth(typed)).toBe(undoDepth(recovered) + 1);
    expect(exact(perform(typed, undo))).toBe(exact(recovered));
  });

  it("rejects out-of-range historical selections and mismatched change or mapping dimensions", () => {
    let state = initial("abcd");
    state = state.update({changes: {from: 0, insert: "x"}, annotations: isolateHistory.of("full")}).state;
    state = state.update({selection: {anchor: 2}, userEvent: "select.pointer",
      annotations: Transaction.time.of(1000)}).state;
    state = state.update({changes: {from: 0, insert: "y"}, annotations: isolateHistory.of("full")}).state;
    const serialized = captureExactHistory(state)!;
    const before = state.toJSON({history: historyField});
    for (const corrupt of [
      (payload: any) => { payload.state.history.done[0].startSelection.ranges[0] = {anchor: 999, head: 999}; },
      (payload: any) => { payload.state.history.done[0].selectionsAfter[0].ranges[0] = {anchor: 999, head: 999}; },
      (payload: any) => { payload.state.history.done[1].changes.push(1); },
      (payload: any) => { payload.state.history.done[1].mapped = [999, -1]; },
      (payload: any) => { payload.state.history.done.push({selectionsAfter: []}); payload.effects.done.push([]); },
    ]) {
      const payload = JSON.parse(serialized);
      corrupt(payload);
      expect(() => restoreExactHistory(JSON.stringify(payload), exact(state), extensions)).toThrow();
      expect(state.toJSON({history: historyField})).toEqual(before);
      expect(exact(state)).toBe("yxabcd");
    }
    const undone = perform(state, undo);
    const redoPayload = JSON.parse(captureExactHistory(undone)!);
    redoPayload.state.history.undone[0].startSelection.ranges[0] = {anchor: 999, head: 999};
    expect(() => restoreExactHistory(JSON.stringify(redoPayload), exact(undone), extensions)).toThrow();
    expect(exact(undone)).toBe("xabcd");
  });

  it("rejects an oversized historical inverse within the history envelope without changing the live state", () => {
    const state = initial("ab").update({changes: {from: 0, to: 1}}).state;
    const payload = JSON.parse(captureExactHistory(state)!);
    payload.state.history.done[0].changes = [[0, "x".repeat(MAX_SOURCE_UTF8_BYTES + 1)], 1];
    const serialized = JSON.stringify(payload);
    expect(new TextEncoder().encode(serialized).byteLength).toBeLessThan(MAX_RECOVERY_HISTORY_BYTES);
    const before = state.toJSON({history: historyField});
    expect(() => restoreExactHistory(serialized, exact(state), extensions)).toThrow();
    expect(state.toJSON({history: historyField})).toEqual(before);
    expect(exact(state)).toBe("b");
    expect(exact(perform(state, undo))).toBe("ab");
  });

  it("rejects recovery metadata that does not match the history document", () => {
    let state = initial("a\r\nb");
    state = state.update({changes: {from: 1, to: 2}}).state;
    const payload = JSON.parse(captureExactHistory(state)!);
    payload.effects.done[0] = [];
    expect(() => restoreExactHistory(JSON.stringify(payload), exact(state), extensions)).toThrow();
  });
});

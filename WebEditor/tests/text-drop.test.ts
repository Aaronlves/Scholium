import {history, redo, undo, undoDepth} from "@codemirror/commands";
import {EditorState, Transaction, type Extension, type TransactionSpec} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {describe, expect, it, vi} from "vitest";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {createTextDropHandlers, insertDroppedText, moveSelectedText} from "../text-transfer";

function harness(source: string, extensions: Extension[] = []) {
  const view = {
    state: EditorState.create({doc: normalizedDocumentText(source),
      extensions: [history(), exactSourceHistory, EditorState.lineSeparator.of("\n"), ...extensions]})
      .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state,
    composing: false,
    focusCount: 0,
    dispatch(spec: TransactionSpec) { this.state = this.state.update(spec).state; },
    focus() { this.focusCount += 1; },
  };
  return view;
}

describe("editor text drops", () => {
  it.each([false, true])("moves/copies original mixed-newline slices and restores exact bytes (copy=%s)", copy => {
    const source = "\uFEFFBefore\r\n##  中文😀e\u0301\nBody\r\n\nAfter\n";
    const view = harness(source);
    const normalized = view.state.doc.toString();
    const from = normalized.indexOf("##"), to = normalized.indexOf("\nAfter");
    view.dispatch({selection: {anchor: from, head: to}});
    const range = view.state.selection.main;
    const payload = view.state.field(exactSourceState).slice(from, to);
    const prefix = "\uFEFFBefore\r\n", suffix = "\nAfter\n";
    expect(moveSelectedText(view, range, view.state.doc.length, copy, true, () => [])).toBe(copy ? "Paste" : "Move");
    expect(view.state.field(exactSourceState).text).toBe((copy ? source : prefix + suffix) + payload);
    expect(undo({state: view.state, dispatch: transaction => { view.state = transaction.state; }})).toBe(true);
    expect(view.state.field(exactSourceState).text).toBe(source);
  });

  it("keeps partial heading text exact and rejects self-moves and protected ranges", () => {
    const view = harness("## Heading\nBody");
    view.dispatch({selection: {anchor: 3, head: 7}});
    const range = view.state.selection.main;
    const before = view.state;
    expect(moveSelectedText(view, range, 5, false, false, () => [])).toBeNull();
    expect(moveSelectedText(view, range, 13, false, false, () => [{from: 0, to: 10}])).toBeNull();
    expect(view.state).toBe(before);
    expect(moveSelectedText(view, range, 13, false, false, () => [])).toBe("Move");
    expect(view.state.doc.toString()).toBe("## ing\nBoHeaddy");
  });

  it("separates a complete unterminated last heading at a new line boundary", () => {
    const view = harness("Before\n\n## Last");
    view.dispatch({selection: {anchor: 8, head: view.state.doc.length}});
    expect(moveSelectedText(view, view.state.selection.main, 0, false, true, () => [])).toBe("Move");
    expect(view.state.doc.toString()).toBe("## Last\nBefore\n\n");
  });

  it("keeps BOM at the file beginning when moving a heading before the first content line", () => {
    const view = harness("\uFEFFBefore\r\n\r\n## Last");
    const from = view.state.doc.toString().indexOf("##");
    view.dispatch({selection: {anchor: from, head: view.state.doc.length}});
    expect(moveSelectedText(view, view.state.selection.main, 1, false, true, () => [])).toBe("Move");
    expect(view.state.field(exactSourceState).text).toBe("\uFEFF## Last\r\nBefore\r\n\r\n");
  });
  it("inserts at the drop target without replacing a different retained selection", () => {
    const view = harness("keep selected text\nend");
    view.dispatch({selection: {anchor: 0, head: 4}});
    expect(insertDroppedText(view, "https://example.test", view.state.doc.length, false, () => [])).toBe("Paste");
    expect(view.state.doc.toString()).toBe("keep selected text\nendhttps://example.test");
    expect(view.state.selection.main.empty).toBe(true);
    expect(view.state.selection.main.head).toBe(view.state.doc.length);
    expect(view.focusCount).toBe(1);
  });

  it.each([null, -1, 4, 0.5, Number.NaN])("rejects invalid target %s without moving selection or focus", position => {
    const view = harness("abc");
    view.dispatch({selection: {anchor: 0, head: 2}});
    const before = view.state;
    expect(insertDroppedText(view, "new", position, false, () => [])).toBeNull();
    expect(view.state).toBe(before);
    expect(view.focusCount).toBe(0);
  });

  it.each(["readOnly", "noneditable", "composing", "pendingComposition"])("preserves %s state", condition => {
    const view = harness("abc", condition === "readOnly" ? [EditorState.readOnly.of(true)]
      : condition === "noneditable" ? [EditorView.editable.of(false)] : []);
    view.composing = condition === "composing";
    const before = view.state;
    expect(insertDroppedText(view, "new", 1, condition === "pendingComposition", () => [])).toBeNull();
    expect(view.state).toBe(before);
    expect(view.focusCount).toBe(0);
  });

  it("checks protected source at the target and rejects without selection side effects", () => {
    const view = harness("protected source");
    const before = view.state;
    expect(insertDroppedText(view, "new", 3, false, target => {
      expect(target.selection.main.head).toBe(3);
      return [{from: 0, to: 9}];
    })).toBeNull();
    expect(view.state).toBe(before);
    expect(view.focusCount).toBe(0);
  });

  it("isolates the drop from adjacent typing and restores exact Unicode and mixed newlines with Undo", () => {
    const source = "\uFEFF甲😀e\u0301\r\n乙\n丙";
    const view = harness(source);
    const exact = () => view.state.field(exactSourceState).text;
    view.dispatch({changes: {from: view.state.doc.length, insert: "!"}, userEvent: "input.type"});
    const before = exact();
    const selection = view.state.selection;
    expect(insertDroppedText(view, "新😀\r\n段", 2, false, () => [])).toBe("Paste");
    const dropped = exact();
    expect(dropped).toBe("\uFEFF甲新😀\r\n段😀e\u0301\r\n乙\n丙!");
    view.dispatch({changes: {from: view.state.selection.main.head, insert: "?"}, userEvent: "input.type"});
    expect(undoDepth(view.state)).toBe(3);
    const run = (command: typeof undo) => expect(command({state: view.state,
      dispatch: transaction => { view.state = transaction.state; }})).toBe(true);
    run(undo);
    expect(exact()).toBe(dropped);
    run(undo);
    expect(exact()).toBe(before);
    expect(view.state.selection.eq(selection)).toBe(true);
    run(redo);
    expect(exact()).toBe(dropped);
  });
});

describe("CodeMirror drop event routing", () => {
  function routing() {
    const view = {...harness("abc"), posAtCoords: () => 1 as number | null};
    view.dispatch({selection: {anchor: 0, head: 1}});
    let identity = 1;
    const inserted: string[] = [];
    const handlers = createTextDropHandlers({documentIdentity: () => identity, compositionActive: () => false,
      protection: () => [], unsupportedFile: () => {}, didInsert: label => inserted.push(label)});
    const event = {clientX: 10, clientY: 20,
      dataTransfer: {files: [], items: [], getData: () => "abc"}};
    return {view, handlers, event, inserted, changeDocument: () => { identity += 1; }};
  }

  it.each([false, true])("owns internal move/copy in one source transaction (Option=%s)", altKey => {
    const {view, handlers, event, inserted} = routing();
    view.posAtCoords = () => 2;
    expect(handlers.dragstart(event, view)).toBe(false);
    const modifiedEvent = {...event, altKey};
    expect(handlers.drop(modifiedEvent, view)).toBe(true);
    expect(view.state.doc.toString()).toBe(altKey ? "abac" : "bac");
    expect(inserted).toEqual([altKey ? "Paste" : "Move"]);
  });

  it.each(["invalidTarget", "composing", "readOnly"])("consumes an internal drop rejected for %s", condition => {
    const {view, handlers, event} = routing();
    handlers.dragstart(event, view);
    if (condition === "invalidTarget") view.posAtCoords = () => null;
    if (condition === "composing") view.composing = true;
    if (condition === "readOnly") view.state = EditorState.create({doc: "abc", extensions: EditorState.readOnly.of(true)});
    const before = view.state;
    expect(handlers.drop(event, view)).toBe(true);
    expect(view.state).toBe(before);
  });

  it.each(["external", "endedDrag", "differentDocument"])("copies %s text without native move fallback", origin => {
    const {view, handlers, event, inserted, changeDocument} = routing();
    if (origin !== "external") handlers.dragstart(event, view);
    if (origin === "endedDrag") handlers.dragend();
    if (origin === "differentDocument") changeDocument();
    expect(handlers.drop(event, view)).toBe(true);
    expect(view.state.doc.toString()).toBe("aabcbc");
    expect(inserted).toEqual(["Paste"]);
    expect(view.focusCount).toBe(1);
  });

  it("does not let a cancelled native drag delete source on a later external drop", () => {
    vi.useFakeTimers();
    try {
      const {view, handlers, event, inserted} = routing();
      const start = {...event, defaultPrevented: false};
      handlers.dragstart(start, view);
      start.defaultPrevented = true;
      vi.runAllTimers();
      expect(handlers.drop(event, view)).toBe(true);
      expect(view.state.doc.toString()).toBe("aabcbc");
      expect(inserted).toEqual(["Paste"]);
    } finally { vi.useRealTimers(); }
  });

  it("rejects a source mutation during a local drag without deleting a stale range", () => {
    const {view, handlers, event} = routing();
    handlers.dragstart(event, view);
    view.dispatch({changes: {from: 0, insert: "new"}});
    const before = view.state;
    expect(handlers.drop(event, view)).toBe(true);
    expect(view.state).toBe(before);
  });
});

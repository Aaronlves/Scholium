import {EditorState, Transaction} from "@codemirror/state";
import {history, redoDepth, undo, undoDepth} from "@codemirror/commands";
import {codeFolding, foldEffect, foldedRanges} from "@codemirror/language";
import {getSearchQuery, SearchQuery, setSearchQuery} from "@codemirror/search";
import {describe, expect, it} from "vitest";
import {createMarkdownDocumentState} from "../bootstrap";
import {documentFindExtension} from "../document-find";
import {captureExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory} from "../exact-source-history";
import {normalizedDocumentText} from "../state";

const extensions = [history(), exactSourceHistory, documentFindExtension, codeFolding(),
  EditorState.lineSeparator.of("\n")];

describe("document initialization in a retained editor runtime", () => {
  it("starts the next document with clean history, find, folding and selection", () => {
    let first = createMarkdownDocumentState("first\r\nsecret\r\n", extensions);
    first = first.update({changes: {from: 5, insert: " edited"},
      selection: {anchor: 3, head: 12}, effects: [
        setSearchQuery.of(new SearchQuery({search: "secret", replace: "hidden"})),
        foldEffect.of({from: 12, to: 19}),
      ]}).state;
    expect(undoDepth(first)).toBe(1);
    expect(foldedRanges(first).size).toBe(1);
    expect(getSearchQuery(first).search).toBe("secret");

    const second = createMarkdownDocumentState("\uFEFFsecond\r\n界😀é\n", extensions);
    expect(second.field(exactSourceState).text).toBe("\uFEFFsecond\r\n界😀é\n");
    expect(second.doc.toString()).toBe(normalizedDocumentText("\uFEFFsecond\r\n界😀é\n"));
    expect(second.selection.main.anchor).toBe(0);
    expect(second.selection.main.head).toBe(0);
    expect(undoDepth(second)).toBe(0);
    expect(redoDepth(second)).toBe(0);
    expect(foldedRanges(second).size).toBe(0);
    expect(getSearchQuery(second).search).toBe("");
    expect(undo({state: second, dispatch: () => { throw new Error("old document Undo escaped"); }}))
      .toBe(false);
  });

  it("keeps exact first-edit Undo local and supports explicit previous-document recovery", () => {
    const source = "\uFEFFA\r\nB\nC\r\n";
    let first = createMarkdownDocumentState(source, extensions);
    first = first.update({changes: {from: 2, to: 3}, selection: {anchor: 3}}).state;
    const recovery = captureExactHistory(first)!;
    const secondSource = "other\r\n";
    let second = createMarkdownDocumentState(secondSource, extensions);
    second = second.update({changes: {from: 0, insert: "new "}}).state;
    expect(undo({state: second, dispatch: transaction => { second = transaction.state; }})).toBe(true);
    expect(second.field(exactSourceState).text).toBe(secondSource);
    expect(undoDepth(second)).toBe(0);

    let restored = restoreExactHistory(recovery, first.field(exactSourceState).text, extensions);
    restored = restored.update({selection: first.selection,
      annotations: Transaction.addToHistory.of(false)}).state;
    expect(restored.selection.eq(first.selection)).toBe(true);
    expect(undo({state: restored, dispatch: transaction => { restored = transaction.state; }})).toBe(true);
    expect(restored.field(exactSourceState).text).toBe(source);
  });
});

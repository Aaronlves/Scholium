import {describe, expect, it} from "vitest";
import {documentFindExtension, documentFindMatches, performDocumentFind, type DocumentFindRequest} from "../document-find";
import {EditorState, Transaction, type TransactionSpec} from "@codemirror/state";
import {history, undoDepth} from "@codemirror/commands";
import type {EditorView} from "@codemirror/view";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";

const request = (
  query: string,
  overrides: Partial<DocumentFindRequest> = {},
): DocumentFindRequest => ({
  query,
  replacement: "",
  caseSensitive: false,
  wholeWord: false,
  action: "update",
  ...overrides,
});

describe("document find", () => {
  function viewFor(source: string) {
    let state = EditorState.create({doc: normalizedDocumentText(source),
      extensions: [documentFindExtension, exactSourceHistory, history(), EditorState.lineSeparator.of("\n")]});
    state = state.update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
    return {get state() { return state; }, dispatch(...specs: TransactionSpec[]) { state = state.update(...specs).state; }} as unknown as EditorView;
  }

  it("rejects oversized Replace All before mutating source, selection, or history", () => {
    const view = viewFor("x".repeat(10_000));
    const selection = view.state.selection;
    expect(() => performDocumentFind(view, request("x", {
      replacement: "y".repeat(1_000), action: "replaceAll",
    }))).toThrow("too large");
    expect(view.state.field(exactSourceState).text).toBe("x".repeat(10_000));
    expect(view.state.selection.eq(selection)).toBe(true);
    expect(undoDepth(view.state)).toBe(0);
  });

  it("checks UTF-8 bytes and exact CRLF overhead for a single replacement", () => {
    const source = "x\r\n" + "a".repeat(7_999_995);
    const view = viewFor(source);
    expect(() => performDocumentFind(view, request("x", {
      replacement: "界界", action: "replaceCurrent",
    }))).toThrow("too large");
    expect(view.state.field(exactSourceState).text).toBe(source);
  });

  it("normalizes inserted CRLF for logical lines and next-match navigation", () => {
    const view = viewFor("x x x\r\n");
    const result = performDocumentFind(view, request("x", {
      replacement: "a\r\nb", action: "replaceCurrent",
    }));
    expect(result.sourceChanged).toBe(true);
    expect(view.state.doc.lines).toBe(3);
    expect(view.state.field(exactSourceState).text).toBe("a\r\nb x x\r\n");
    expect(view.state.selection.main.from).toBe(4);
  });
  it("uses literal, case-insensitive matching by default", () => {
    expect(documentFindMatches("Value value a.b axb", request("value"))).toEqual([
      {from: 0, to: 5},
      {from: 6, to: 11},
    ]);
    expect(documentFindMatches("a.b axb", request("a.b"))).toEqual([
      {from: 0, to: 3},
    ]);
  });

  it("respects case-sensitive and whole-word options", () => {
    expect(documentFindMatches(
      "Value value valuable",
      request("value", {caseSensitive: true}),
    )).toEqual([{from: 6, to: 11}]);
    expect(documentFindMatches(
      "value valuable value",
      request("value", {wholeWord: true}),
    )).toEqual([{from: 0, to: 5}, {from: 15, to: 20}]);
  });
});

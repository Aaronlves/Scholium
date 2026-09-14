import {describe, expect, it} from "vitest";
import {EditorState} from "@codemirror/state";
import {history, isolateHistory, undo} from "@codemirror/commands";
import {passageReplacement} from "../passage-replacement";
import {applyNormalizedChangesToExactSource, normalizedDocumentText} from "../state";
import {compositionRequestPolicy} from "../composition";

describe("adopt exact passage", () => {
  it("preserves BOM, mixed newlines and unrelated bytes, and forms a single undo operation", () => {
    const source = "\uFEFF---\r\nunknown: 'keep'\r\n---\n原文 😀。\r\n尾段\n";
    const from = source.indexOf("原文"), to = source.indexOf("。") + 1;
    const change = passageReplacement(source, source, from, to, "更清楚的原文 😀。");
    expect(change).not.toBeNull();
    expect(applyNormalizedChangesToExactSource(source, [change!]))
      .toBe(source.slice(0, from) + "更清楚的原文 😀。" + source.slice(to));
    let state = EditorState.create({doc: normalizedDocumentText(source), extensions: [history()]});
    state = state.update({changes: change!, annotations: isolateHistory.of("full")}).state;
    expect(undo({state, dispatch: transaction => { state = transaction.state; }})).toBe(true);
    expect(state.doc.toString()).toBe(normalizedDocumentText(source));
  });
  it("inserts an identity without selecting the paragraph and undoes exactly once", () => {
    const source = "\uFEFFParagraph 😀.\r\n\r\nFollowing.";
    const insertion = source.indexOf("\r\n");
    const change = passageReplacement(source, source, insertion, insertion, " ^one")!;
    let state = EditorState.create({doc: normalizedDocumentText(source), selection: {anchor: 2, head: 6}, extensions: [history()]});
    state = state.update({changes: change, annotations: isolateHistory.of("full")}).state;
    expect(state.selection.main.anchor).toBe(2);
    expect(state.selection.main.head).toBe(6);
    expect(applyNormalizedChangesToExactSource(source, [change])).toBe(source.slice(0, insertion) + " ^one" + source.slice(insertion));
    expect(undo({state, dispatch: transaction => { state = transaction.state; }})).toBe(true);
    expect(state.doc.toString()).toBe(normalizedDocumentText(source));
    expect(passageReplacement("😀x", "😀x", 1, 1, " ^one")).toBeNull();
    expect(passageReplacement("a\r\nb", "a\r\nb", 2, 2, " ^one")).toBeNull();
    expect(passageReplacement("abc", "abc", 1, 1, "")).toBeNull();
    expect(passageReplacement("\uFEFFtext", "\uFEFFtext", 0, 0, "prefix")).toBeNull();
  });
  it("rejects later edits, split surrogate pairs, split CRLF, empty proposals and composition", () => {
    expect(passageReplacement("later", "older", 0, 3, "new")).toBeNull();
    expect(passageReplacement("😀x", "😀x", 1, 2, "new")).toBeNull();
    expect(passageReplacement("a\r\nb", "a\r\nb", 0, 2, "new")).toBeNull();
    expect(passageReplacement("abc", "abc", 0, 2, "")).toBeNull();
    expect(compositionRequestPolicy("replacePassage")).toBe("reject");
  });
});

import {EditorState, StateEffect} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {
  activeProjectionSignature,
  selectionAffectedProjectionRanges,
  selectionIntersectsProjection,
  transactionCanMapProjection,
  transactionChangedSyntaxTree,
  transactionMayCreateProjection,
} from "../projection-update";
import {scholiumNoteLanguage} from "../language";

function insertion(text: string) {
  const state = EditorState.create({doc: "研究文本"});
  return state.update({changes: {from: state.doc.length, insert: text}});
}

describe("empty projection update fast path", () => {
  it("detects a parse-tree-only state update", () => {
    const state = EditorState.create({doc: "# Claim\n"});
    const transaction = state.update({
      effects: StateEffect.reconfigure.of([scholiumNoteLanguage]),
    });

    expect(transaction.docChanged).toBe(false);
    expect(transactionChangedSyntaxTree(transaction)).toBe(true);
  });

  it("does not treat a pure selection transaction as a structural parse update", () => {
    const state = EditorState.create({
      doc: "# Claim\n\nParagraph",
      extensions: [scholiumNoteLanguage],
    });
    const transaction = state.update({selection: {anchor: state.doc.length}});
    expect(transaction.docChanged).toBe(false);
    expect(transactionChangedSyntaxTree(transaction)).toBe(false);
  });

  it("keeps 1,000 parsed same-paragraph arrow transactions local and index-stable", () => {
    let state = EditorState.create({
      doc: `Paragraph ${"x".repeat(1_100)}`,
      extensions: [scholiumNoteLanguage],
      selection: {anchor: 1},
    });
    expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();

    for (let offset = 2; offset <= 1_001; offset += 1) {
      const transaction = state.update({selection: {anchor: offset}});
      const requiresFullIndexRebuild = transaction.docChanged
        || transactionChangedSyntaxTree(transaction);
      const affected = selectionAffectedProjectionRanges(
        transaction.state.doc.length,
        transaction.startState.selection.ranges,
        transaction.state.selection.ranges,
      );
      const affectedUTF16Count = affected.reduce(
        (total, range) => total + range.to - range.from,
        0,
      );

      expect(requiresFullIndexRebuild).toBe(false);
      expect(affectedUTF16Count).toBeLessThanOrEqual(4_002);
      state = transaction.state;
    }
  });

  it("reuses an empty projection for ordinary mixed-script insertion", () => {
    const transaction = insertion("继续 argument 🧭");

    expect(transactionMayCreateProjection(transaction, /\|/)).toBe(false);
    expect(transactionMayCreateProjection(transaction, /[>\[\]!]/)).toBe(false);
    expect(transactionMayCreateProjection(transaction, /[\[\]\^:]/)).toBe(false);
  });

  it("rebuilds when plain letters complete syntax beside structural markers", () => {
    const callout = EditorState.create({doc: "> [!] Claim"});
    const calloutInsertion = callout.update({changes: {from: 4, insert: "state"}});
    expect(transactionMayCreateProjection(calloutInsertion, /[>\[\]!]/)).toBe(true);

    const footnote = EditorState.create({doc: "[^]: Definition"});
    const footnoteInsertion = footnote.update({changes: {from: 2, insert: "note"}});
    expect(transactionMayCreateProjection(footnoteInsertion, /[\[\]\^:]/)).toBe(true);
  });

  it("rebuilds for syntax markers, deletions, and unbounded insertions", () => {
    expect(transactionMayCreateProjection(insertion("|"), /\|/)).toBe(true);
    expect(transactionMayCreateProjection(insertion("[!state]"), /[>\[\]!]/)).toBe(true);
    expect(transactionMayCreateProjection(insertion("[^note]:"), /[\[\]\^:]/)).toBe(true);

    const state = EditorState.create({doc: "a|b"});
    expect(transactionMayCreateProjection(
      state.update({changes: {from: 1, to: 2}}),
      /\|/,
    )).toBe(true);
    expect(transactionMayCreateProjection(insertion("x".repeat(8_193)), /\|/)).toBe(true);
  });
});

describe("construct-bearing projection update fast path", () => {
  const source = "ordinary prose\n\n| A | B |\n| - | - |\n| 1 | 2 |\n";
  const tableFrom = source.indexOf("| A");
  const range = {from: tableFrom, to: source.length};

  it("maps a bounded plain-text insertion outside the indexed construct", () => {
    const state = EditorState.create({doc: source});
    const transaction = state.update({changes: {from: 8, insert: " argument"}});

    expect(transactionCanMapProjection(transaction, /\|/, [range])).toBe(true);
    expect(transaction.changes.mapPos(range.from)).toBe(range.from + 9);
  });

  it("rebuilds for structural, boundary, interior, deletion, and multiline edits", () => {
    const state = EditorState.create({doc: source});
    expect(transactionCanMapProjection(
      state.update({changes: {from: 8, insert: "|"}}),
      /\|/,
      [range],
    )).toBe(false);
    expect(transactionCanMapProjection(
      state.update({changes: {from: range.from, insert: "x"}}),
      /\|/,
      [range],
    )).toBe(false);
    expect(transactionCanMapProjection(
      state.update({changes: {from: range.from + 2, insert: "x"}}),
      /\|/,
      [range],
    )).toBe(false);
    expect(transactionCanMapProjection(
      state.update({changes: {from: 2, to: 3}}),
      /\|/,
      [range],
    )).toBe(false);
    expect(transactionCanMapProjection(
      state.update({changes: {from: 8, insert: "new\nline"}}),
      /\|/,
      [range],
    )).toBe(false);
  });

  it("does not map an unrelated index past locally completed latent syntax", () => {
    const latent = "> [!] Claim\n\n| A | B |\n| - | - |";
    const tableFrom = latent.indexOf("| A");
    const state = EditorState.create({doc: latent});
    const transaction = state.update({changes: {from: 4, insert: "state"}});
    expect(transactionCanMapProjection(
      transaction,
      /[>\[\]!]/,
      [{from: tableFrom, to: latent.length}],
    )).toBe(false);
  });
});

describe("projection activation boundaries", () => {
  const projection = {from: 4, to: 12};
  const caret = (head: number) => ({from: head, to: head, head, empty: true});

  it("uses half-open caret boundaries and real selection overlap", () => {
    expect(selectionIntersectsProjection(caret(3), projection)).toBe(false);
    expect(selectionIntersectsProjection(caret(4), projection)).toBe(true);
    expect(selectionIntersectsProjection(caret(11), projection)).toBe(true);
    expect(selectionIntersectsProjection(caret(12), projection)).toBe(false);
    expect(selectionIntersectsProjection(
      {from: 0, to: 4, head: 4, empty: false},
      projection,
    )).toBe(false);
    expect(selectionIntersectsProjection(
      {from: 0, to: 5, head: 5, empty: false},
      projection,
    )).toBe(true);
  });

  it("keeps one signature while the caret remains inside a construct", () => {
    expect(activeProjectionSignature([caret(5)], [projection])).toBe("4:12");
    expect(activeProjectionSignature([caret(10)], [projection])).toBe("4:12");
    expect(activeProjectionSignature([caret(12)], [projection])).toBe("");
  });
});

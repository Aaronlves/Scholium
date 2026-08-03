import {EditorState, StateEffect} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {
  activeProjectionSignature,
  selectionAffectedProjectionRanges,
  selectionActivatesCallout,
  selectionIntersectsProjection,
  selectionProjectionSignature,
  transactionCanMapProjection,
  transactionCanMapProjectionTopology,
  transactionChangedSyntaxTree,
  transactionMayCreateProjection,
} from "../projection-update";
import {scholiumNoteLanguage} from "../language";
import {semanticProjectionRanges} from "../semantic-projection";

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

describe("local projection-topology proof", () => {
  function parsedState(source: string) {
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
    return state;
  }

  function syntaxFor(state: EditorState) {
    return semanticProjectionRanges(state, [{from: 0, to: state.doc.length}], 0);
  }

  it("maps ordinary prose beside rich inline Markdown without a full catalog rebuild", () => {
    const source = "The shrimp is *Neocaridina davidi* and **Scholium** remains stable.";
    const state = parsedState(source);
    const insertionPoint = source.indexOf("shrimp") + "shrimp".length;
    const transaction = state.update({changes: {from: insertionPoint, insert: " species"}});

    expect(transactionCanMapProjectionTopology(
      transaction,
      /[\r\n`~<>%$\[\]!*_|^:]/,
      [],
      syntaxFor(state),
    )).toBe(true);
  });

  it("rebuilds when plain text completes latent inline or Callout syntax", () => {
    const emphasisSource = "Before **** after";
    const emphasis = parsedState(emphasisSource);
    const emphasisTransaction = emphasis.update({
      changes: {from: emphasisSource.indexOf("****") + 2, insert: "claim"},
    });
    expect(transactionCanMapProjectionTopology(
      emphasisTransaction,
      /[\r\n`~<>%$\[\]!*_|^:]/,
      [],
      syntaxFor(emphasis),
    )).toBe(false);

    const calloutSource = "> [!] Claim";
    const callout = parsedState(calloutSource);
    const calloutTransaction = callout.update({changes: {from: 4, insert: "state"}});
    expect(transactionCanMapProjectionTopology(
      calloutTransaction,
      /[\r\n`~<>%$\[\]!*_|^:]/,
      [],
      syntaxFor(callout),
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

  it("keeps the Callout content-end insertion point editable", () => {
    expect(selectionActivatesCallout(caret(3), projection)).toBe(false);
    expect(selectionActivatesCallout(caret(4), projection)).toBe(true);
    expect(selectionActivatesCallout(caret(12), projection)).toBe(true);
    expect(selectionActivatesCallout(caret(13), projection)).toBe(false);
    expect(selectionActivatesCallout(
      {from: 0, to: 4, head: 4, empty: false},
      projection,
    )).toBe(false);
  });

  it("keeps one signature while the caret remains inside a construct", () => {
    expect(activeProjectionSignature([caret(5)], [projection])).toBe("4:12");
    expect(activeProjectionSignature([caret(10)], [projection])).toBe("4:12");
    expect(activeProjectionSignature([caret(12)], [projection])).toBe("");
  });

  it("distinguishes a list prefix from prose on the same physical line", () => {
    const state = EditorState.create({doc: "- stable list body"});
    const prefix = {from: 0, to: 2};

    expect(selectionProjectionSignature(state.doc, [caret(0)], [], [prefix]))
      .not.toBe(selectionProjectionSignature(state.doc, [caret(8)], [], [prefix]));
    expect(selectionProjectionSignature(state.doc, [caret(8)], [], [prefix]))
      .toBe(selectionProjectionSignature(state.doc, [caret(12)], [], [prefix]));
  });

  it("invalidates presentation only across physical-line or inline-construct boundaries", () => {
    const source = "plain **first** between **second**\nnext";
    const state = EditorState.create({doc: source});
    const firstFrom = source.indexOf("**first**");
    const secondFrom = source.indexOf("**second**");
    const projections = [
      {from: firstFrom, to: firstFrom + "**first**".length},
      {from: secondFrom, to: secondFrom + "**second**".length},
    ];
    const signature = (head: number) => selectionProjectionSignature(
      state.doc,
      [caret(head)],
      projections,
    );

    expect(signature(1)).toBe(signature(3));
    expect(signature(firstFrom + 2)).toBe(signature(firstFrom + 5));
    expect(signature(1)).not.toBe(signature(firstFrom + 2));
    expect(signature(firstFrom + 2)).not.toBe(signature(secondFrom + 2));
    expect(signature(1)).not.toBe(signature(source.indexOf("next")));
  });
});

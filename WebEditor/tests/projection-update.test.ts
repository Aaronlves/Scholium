import {EditorState, StateEffect} from "@codemirror/state";
import {describe, expect, it} from "vitest";
import {
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

  it("reuses an empty projection for ordinary mixed-script insertion", () => {
    const transaction = insertion("继续 argument 🧭");

    expect(transactionMayCreateProjection(transaction, /\|/)).toBe(false);
    expect(transactionMayCreateProjection(transaction, /[>\[\]!]/)).toBe(false);
    expect(transactionMayCreateProjection(transaction, /[\[\]\^:]/)).toBe(false);
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
});

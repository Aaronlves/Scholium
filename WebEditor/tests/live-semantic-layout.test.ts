import {EditorSelection, EditorState} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {describe, expect, it} from "vitest";
import {scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSemanticLayout, semanticSpacingBlocks} from "../live-semantic-layout";
import {transactionChangedSyntaxTree} from "../projection-update";
import type {SemanticBlockProjection} from "../semantic-projection";

function block(kind: SemanticBlockProjection["kind"], from: number, to: number,
  parent: string | null = null): SemanticBlockProjection {
  return {kind, from, to, parent: parent ? {kind: "blockQuote", from, to} : null, nodeName: kind, depth: 0, headingLevel: null,
    listDepth: null, markerRanges: [], taskMarkerRange: null};
}

// Deliberately simple exhaustive oracle for interval ownership. It is not a
// production fallback: adversarial overlap/equal-start cases exercise the sweep.
const priorities: Partial<Record<SemanticBlockProjection["kind"], number>> = {
  callout: 100, displayMath: 90, table: 80, code: 70, html: 60,
  orderedList: 50, unorderedList: 50, blockQuote: 40, thematicBreak: 30,
  heading: 20, paragraph: 10,
};
function exhaustiveOwners(blocks: readonly SemanticBlockProjection[], end: number) {
  const candidates = blocks.filter(b => b.parent === null && b.to > end);
  return candidates.filter(candidate => !candidates.some(owner => owner !== candidate
    && owner.from <= candidate.from && owner.to >= candidate.to
    && (priorities[owner.kind] ?? 0) > (priorities[candidate.kind] ?? 0)))
    .sort((a, b) => a.from - b.from || a.to - b.to);
}

function layoutState(source: string, selection = EditorSelection.cursor(0)) {
  const projections = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
  const layout = createLiveSemanticLayout({projections, editingDialect: () => null, selection: {
    extension: [], selection: state => state.selection,
    changed: (a, b) => !a.selection.eq(b.selection),
  }});
  const state = EditorState.create({doc: source, selection: EditorSelection.create([selection]),
    extensions: [scholiumNoteLanguage, projections.extension, layout.extension]});
  return {state, projections};
}
function decorationEntries(state: EditorState) {
  return state.facet(EditorView.decorations).flatMap(set => {
    if (typeof set === "function") return [];
    const entries = [];
    for (let cursor = set.iter(); cursor.value; cursor.next()) {
      entries.push({from: cursor.from, to: cursor.to, decoration: cursor.value});
    }
    return entries;
  });
}
function spacingEntries(state: EditorState) {
  return decorationEntries(state).filter(({decoration}) =>
    decoration.spec.widget || decoration.spec.attributes?.class?.includes("cm-live-semantic-blank-gap"));
}
function snapshot(state: EditorState) {
  return decorationEntries(state).map(({from, to, decoration}) => ({from, to, spec: decoration.spec}));
}

describe("semantic block spacing ownership", () => {
  it("preserves equal-priority, partial-overlap and nested-source ownership", () => {
    const blocks = [block("paragraph", 0, 10), block("callout", 0, 20),
      block("blockQuote", 0, 20), block("table", 10, 30),
      block("paragraph", 15, 25), block("orderedList", 40, 80),
      block("unorderedList", 40, 80), block("comment", 90, 110),
      block("paragraph", 50, 60, "OrderedList")];
    expect(semanticSpacingBlocks(blocks)).toEqual(exhaustiveOwners(blocks, 0));
    expect(semanticSpacingBlocks(blocks, 20)).toEqual(exhaustiveOwners(blocks, 20));
  });

  it("agrees with exhaustive ownership on seeded overlapping intervals without mutating the index", () => {
    let seed = 0x12345678;
    const next = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
    const kinds = [...Object.keys(priorities), "comment"] as SemanticBlockProjection["kind"][];
    for (let trial = 0; trial < 100; trial++) {
      const blocks = Array.from({length: 100}, () => {
        const from = next() % 100;
        return Object.freeze(block(kinds[next() % kinds.length], from, from + 1 + next() % 40,
          next() % 7 === 0 ? "Blockquote" : null));
      });
      Object.freeze(blocks);
      const end = next() % 20;
      expect(semanticSpacingBlocks(blocks, end)).toEqual(exhaustiveOwners(blocks, end));
    }
  });
});

describe("incremental semantic spacing", () => {
  it.each(["blank", "code", "callout"])("updates distant %s activation when an edit also moves the caret", active => {
    const source = "First ordinary prose.\n\nMiddle prose.\n\n```ts\nconst value = 1;\n```\n\n> [!state] Claim\n> Body.\n\nTail.";
    const anchor = active === "blank" ? source.indexOf("\n\n") + 1
      : source.indexOf(active === "code" ? "value" : "Body");
    const {state, projections} = layoutState(source, EditorSelection.cursor(anchor));
    const transaction = state.update({changes: {from: 7, insert: "new "}, selection: {anchor: 11}});
    expect(projections.topologyWasMapped(transaction)).toBe(true);
    expect(snapshot(transaction.state)).toEqual(snapshot(layoutState(
      transaction.newDoc.toString(), transaction.state.selection.main,
    ).state));
  });

  it("retains unaffected line decorations during ordinary input", () => {
    const {state} = layoutState("First ordinary prose.\n\nMiddle prose.\n\nLast prose.");
    const previous = decorationEntries(state).find(entry => entry.from === state.doc.line(5).from)!;
    const transaction = state.update({changes: {from: 7, insert: "new "}});
    const after = decorationEntries(transaction.state).find(entry =>
      entry.from === transaction.state.doc.line(5).from)!;
    expect(after.decoration).toBe(previous.decoration);
  });
  it("reuses spacing despite a changed parse tree for topology-preserving typing", () => {
    const {state, projections} = layoutState("Ordinary 中文 prose.\n\n> A quotation.\n\nTail.");
    const old = spacingEntries(state);
    expect(old.length).toBeGreaterThan(0);
    const transaction = state.update({changes: {from: 8, insert: "more "}});
    expect(transactionChangedSyntaxTree(transaction)).toBe(true);
    expect(projections.topologyWasMapped(transaction)).toBe(true);
    const mapped = spacingEntries(transaction.state);
    expect(mapped.length).toBe(old.length);
    mapped.forEach((entry, i) => {
      expect(entry.decoration).toBe(old[i].decoration);
      expect(entry.from).toBe(transaction.changes.mapPos(old[i].from));
      expect(entry.decoration.spec.attributes?.["data-scholium-blank-source-offset"]).toBeUndefined();
    });
    expect(snapshot(transaction.state)).toEqual(snapshot(layoutState(transaction.newDoc.toString()).state));
  });

  it.each([
    "Ordinary 中文 e\u0301 😀 prose.\n\n> A quotation.\n\nTail.",
    "---\ntitle: Example\n---\n\nOrdinary prose.\n\n# Heading\n\nTail.",
    "Ordinary prose.\n\n```ts\nconst x = 1;\n```\n\nTail.",
    "Ordinary prose.\n\n> [!state] Claim\n> Body.\n\n- item\n\nTail.",
  ])("agrees with fresh layout through insertion, deletion and structural edits: %s", source => {
    let {state} = layoutState(source);
    const start = source.indexOf("Ordinary") + 4;
    const edits = [
      {from: start, insert: "中文"},
      {from: start, to: start + 2},
      {from: start, insert: "\n\n## New heading\n\n"},
      {from: 0, insert: "Intro.\n\n"},
      {from: 0, to: 8},
    ];
    for (const changes of edits) {
      state = state.update({changes}).state;
      expect(snapshot(state)).toEqual(snapshot(layoutState(state.doc.toString(), state.selection.main).state));
    }
  });
});

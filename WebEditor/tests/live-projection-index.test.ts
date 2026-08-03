import {EditorState} from "@codemirror/state";
import {describe, expect, it} from "vitest";
import {scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import type {MarkdownEditingDialect} from "../protocol";

const dialect: MarkdownEditingDialect = {
  version: 4,
  callouts: [
    {identifier: "state", aliases: [], label: "Statement", meaning: "Statement"},
  ],
  vectorLinkOperators: [
    {marker: "", kind: "neutral", meaning: "Neutral"},
    {marker: "+", kind: "supports", meaning: "Supports"},
    {marker: "-", kind: "opposes", meaning: "Opposes"},
    {marker: "?", kind: "incompatible", meaning: "Incompatible"},
  ],
  footnotes: {
    namedReferenceOpening: "[^",
    namedReferenceClosing: "]",
    definitionSeparator: ":",
    inlineOpening: "^[",
    continuationIndentSpaces: 2,
    allowsTabContinuation: true,
    caseSensitiveIdentifiers: true,
    ordinalByFirstReference: true,
  },
  mathematics: {
    inlineDelimiter: "$",
    displayDelimiter: "$$",
    singleDollarInline: true,
  },
};

describe("live projection index component", () => {
  it("owns catalog construction and maps only topology-safe prose edits", () => {
    const metrics: string[] = [];
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: (name) => metrics.push(name),
    });
    const source = "> [!state] Claim\n> Body.\n\nPlain prose with $x$.";
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const initial = controller.index(state);
    expect(initial.callouts).toHaveLength(1);
    expect(initial.mathExpressions.map((expression) => expression.content)).toEqual(["x"]);

    const proseInsertion = source.indexOf("Plain") + "Plain".length;
    const proseTransaction = state.update({
      changes: {from: proseInsertion, insert: " ordinary"},
    });
    const mapped = controller.index(proseTransaction.state);
    expect(mapped.topologyIdentity).toBe(initial.topologyIdentity);
    expect(controller.topologyWasMapped(proseTransaction)).toBe(true);

    const structuralTransaction = proseTransaction.state.update({
      changes: {from: proseTransaction.state.doc.length, insert: "\n\n**New**"},
    });
    const rebuilt = controller.index(structuralTransaction.state);
    expect(rebuilt.topologyIdentity).not.toBe(mapped.topologyIdentity);
    expect(metrics).toContain("projection-index");
  });

  it("owns a complete syntax catalog beyond CodeMirror's initial viewport", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = `${"ordinary prose ".repeat(300)}\n\n$x$.`;
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });

    expect(controller.index(state).mathExpressions.map((expression) => expression.content))
      .toEqual(["x"]);
  });

  it("extends a proven Callout across its trailing quote-only edit line", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = "> [!state] Claim\n> ";
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const index = controller.index(state);

    expect(index.syntax.blocks.find((block) => block.kind === "callout")?.to)
      .toBeLessThan(source.length);
    expect(index.callouts).toEqual([{from: 0, to: source.length, source}]);
  });

  it("rebuilds cached Callout source when Return appends a quote-only line", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = "> [!state] Claim";
    const state = EditorState.create({
      doc: source,
      selection: {anchor: source.length},
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const initial = controller.index(state);
    const continued = source + "\n> ";
    const transaction = state.update({
      changes: {from: source.length, insert: "\n> "},
      selection: {anchor: continued.length},
    });
    const next = controller.index(transaction.state);

    expect(next.topologyIdentity).not.toBe(initial.topologyIdentity);
    expect(next.callouts).toEqual([{from: 0, to: continued.length, source: continued}]);
    expect(next.syntax.blocks.find((block) => block.kind === "callout")?.markerRanges
      .map((range) => continued.slice(range.from, range.to)))
      .toEqual([">", "[!state]", ">"]);
  });
});

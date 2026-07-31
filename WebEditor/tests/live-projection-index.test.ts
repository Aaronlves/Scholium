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
});

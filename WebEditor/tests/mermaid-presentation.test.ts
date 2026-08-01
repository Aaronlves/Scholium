import {EditorState} from "@codemirror/state";
import {describe, expect, it} from "vitest";
import {mermaidPresentation} from "../mermaid-presentation";
import type {SemanticCodeBlockRange} from "../live-projection-index";

function blockFor(source: string): SemanticCodeBlockRange {
  const closing = source.lastIndexOf("```");
  return {
    from: 0,
    to: source.length,
    fenced: true,
    markerRanges: [{from: 0, to: 3}, {from: closing, to: closing + 3}],
  };
}

describe("Mermaid fenced-code presentation", () => {
  it("recognizes only the fenced-code info string and retains exact source offsets", () => {
    const source = "```mermaid\nflowchart LR\n  A --> B\n```\n";
    const doc = EditorState.create({doc: source}).doc;
    const presentation = mermaidPresentation(doc, blockFor(source));

    expect(presentation).not.toBeNull();
    expect(presentation?.source).toBe(source);
    expect(presentation?.content).toBe("flowchart LR\n  A --> B");
    expect(doc.sliceString(presentation!.contentFrom, presentation!.contentTo)).toBe("flowchart LR\n  A --> B\n");
  });

  it("does not reinterpret ordinary or unclosed fenced code", () => {
    const ordinary = "```typescript\nconst mermaid = true\n```\n";
    const ordinaryDoc = EditorState.create({doc: ordinary}).doc;
    expect(mermaidPresentation(ordinaryDoc, blockFor(ordinary))).toBeNull();
    expect(mermaidPresentation(ordinaryDoc, {
      from: 0,
      to: ordinary.length,
      fenced: true,
      markerRanges: [{from: 0, to: 3}],
    })).toBeNull();
  });
});

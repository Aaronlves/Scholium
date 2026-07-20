import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {rangeKey, semanticProjectionRanges} from "../semantic-projection";
import {scholiumNoteLanguage} from "../language";

describe("Lezer-backed semantic projection", () => {
  function completeProjection(source: string) {
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
    if (!tree) throw new Error("Expected the semantic syntax tree to complete.");
    return semanticProjectionRanges(state, [{from: 0, to: source.length}], 2_000, tree);
  }

  it("proves representative standard Markdown ranges", () => {
    const source = "## Claim\n\n**strong**, *emphasis*, and ==highlight== with [link](https://example.test).\n\n| A | B |\n|---|---|\n| 1 | 2 |";
    const ranges = completeProjection(source);
    const strongFrom = source.indexOf("**strong**");
    const emphasisFrom = source.indexOf("*emphasis*");
    const linkFrom = source.indexOf("[link]");
    const highlightFrom = source.indexOf("==highlight==");

    expect(ranges.headingLevelByLineFrom.get(0)).toBe(2);
    expect(ranges.strong.has(rangeKey(strongFrom, strongFrom + "**strong**".length))).toBe(true);
    expect(ranges.emphasis.has(rangeKey(emphasisFrom, emphasisFrom + "*emphasis*".length))).toBe(true);
    expect(ranges.links.has(rangeKey(linkFrom, linkFrom + "[link](https://example.test)".length))).toBe(true);
    expect(ranges.highlights.has(rangeKey(highlightFrom, highlightFrom + "==highlight==".length))).toBe(true);
    expect(ranges.tables).toHaveLength(1);
  });

  it("does not project malformed markers as semantics", () => {
    const source = "##no heading\n**unfinished\n[broken](";
    const ranges = completeProjection(source);
    expect(ranges.headingLevelByLineFrom.size).toBe(0);
    expect(ranges.strong.size).toBe(0);
    expect(ranges.links.has(rangeKey(source.indexOf("[broken]"), source.length))).toBe(false);
  });

  it("distinguishes semantic callout blocks from ordinary quotations", () => {
    const source = "> [!state] Claim\n> Supported body.\n\n> Ordinary quotation.";
    const ranges = completeProjection(source);
    const calloutEnd = source.indexOf("\n\n");

    expect(ranges.callouts).toEqual([{from: 0, to: calloutEnd}]);
  });
});

import {EditorState} from "@codemirror/state";
import {markdown, markdownLanguage} from "@codemirror/lang-markdown";
import {describe, expect, it} from "vitest";
import {rangeKey, semanticProjectionRanges} from "../semantic-projection";

describe("Lezer-backed semantic projection", () => {
  it("proves representative standard Markdown ranges", () => {
    const source = "## Claim\n\n**strong** and *emphasis* with [link](https://example.test).\n\n| A | B |\n|---|---|\n| 1 | 2 |";
    const state = EditorState.create({doc: source, extensions: [markdown({base: markdownLanguage})]});
    const ranges = semanticProjectionRanges(state, [{from: 0, to: source.length}]);
    const strongFrom = source.indexOf("**strong**");
    const emphasisFrom = source.indexOf("*emphasis*");
    const linkFrom = source.indexOf("[link]");

    expect(ranges.headingLevelByLineFrom.get(0)).toBe(2);
    expect(ranges.strong.has(rangeKey(strongFrom, strongFrom + "**strong**".length))).toBe(true);
    expect(ranges.emphasis.has(rangeKey(emphasisFrom, emphasisFrom + "*emphasis*".length))).toBe(true);
    expect(ranges.links.has(rangeKey(linkFrom, linkFrom + "[link](https://example.test)".length))).toBe(true);
    expect(ranges.tables).toHaveLength(1);
  });

  it("does not project malformed markers as semantics", () => {
    const source = "##no heading\n**unfinished\n[broken](";
    const state = EditorState.create({doc: source, extensions: [markdown({base: markdownLanguage})]});
    const ranges = semanticProjectionRanges(state, [{from: 0, to: source.length}]);
    expect(ranges.headingLevelByLineFrom.size).toBe(0);
    expect(ranges.strong.size).toBe(0);
    expect(ranges.links.has(rangeKey(source.indexOf("[broken]"), source.length))).toBe(false);
  });
});

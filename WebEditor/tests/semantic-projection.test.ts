import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {
  boundedLinePrefix,
  boundedProjectionRanges,
  mapSemanticProjectionRanges,
  rangeKey,
  semanticProjectionRanges,
} from "../semantic-projection";
import {scholiumNoteLanguage} from "../language";

describe("Lezer-backed semantic projection", () => {
  it("reads only a bounded marker prefix from a 100,000-unit interaction line", () => {
    const state = EditorState.create({doc: `> [!state] ${"x".repeat(99_989)}`});
    const prefix = boundedLinePrefix(state.doc, state.doc.length, 512);

    expect(prefix).toHaveLength(512);
    expect(prefix.startsWith("> [!state] ")).toBe(true);
  });

  it("keeps a wrapped viewport bounded inside a 100,000-unit physical line", () => {
    const ranges = boundedProjectionRanges(100_000, [{from: 48_000, to: 49_000}], 2_000);
    expect(ranges).toEqual([{from: 46_000, to: 51_000}]);
    expect(ranges[0].to - ranges[0].from).toBe(5_000);
  });
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

  it("projects the first H1 after closed frontmatter together with later headings", () => {
    const source = "---\ntitle: Fixture\n---\n# Document title\n\n## Section";
    const ranges = completeProjection(source);

    expect(ranges.headingLevelByLineFrom.get(source.indexOf("# Document"))).toBe(1);
    expect(ranges.headingLevelByLineFrom.get(source.indexOf("## Section"))).toBe(2);
  });

  it("does not project malformed markers as semantics", () => {
    const source = "##no heading\n**unfinished\n[broken](";
    const ranges = completeProjection(source);
    expect(ranges.headingLevelByLineFrom.size).toBe(0);
    expect(ranges.strong.size).toBe(0);
    expect(ranges.links.has(rangeKey(source.indexOf("[broken]"), source.length))).toBe(false);
  });

  it("distinguishes semantic callout blocks from ordinary quotations", () => {
    const source = "> [!state]- Claim\n> Supported body.\n\n> Ordinary quotation.";
    const ranges = completeProjection(source);
    const calloutEnd = source.indexOf("\n\n");

    expect(ranges.callouts).toEqual([{from: 0, to: calloutEnd}]);
    expect(ranges.blocks.find((block) => block.kind === "callout")?.markerRanges
      .map((range) => source.slice(range.from, range.to))).toEqual([">", "[!state]-", ">"]);
  });

  it("owns marker ranges and nesting for both presentation adapters", () => {
    const source = [
      "## ATX heading",
      "",
      "Setext title",
      "============",
      "",
      "> Quote with **strong** and [link](target.md).",
      "[[Target Note|Visible alias]] and [[Source Note]]{{A long annotation.}}",
      "",
      "- [x] Task",
      "  - Nested",
    ].join("\n");
    const ranges = completeProjection(source);
    const headings = ranges.blocks.filter((block) => block.kind === "heading");
    const quote = ranges.blocks.find((block) => block.kind === "blockQuote");
    const items = ranges.blocks.filter((block) => block.kind === "listItem");
    const strong = ranges.inlines.find((inline) => inline.kind === "strong");
    const link = ranges.inlines.find((inline) => inline.kind === "link");
    const wikilinks = ranges.inlines.filter((inline) => inline.kind === "wikilink");
    const wikilink = wikilinks[0];
    const annotatedLink = wikilinks[1];

    expect(headings[0]).toMatchObject({headingLevel: 2, depth: 0, parent: null});
    expect(headings[0]?.markerRanges.map((range) => source.slice(range.from, range.to)))
      .toEqual(["## "]);
    expect(headings[1]).toMatchObject({headingLevel: 1, depth: 0, parent: null});
    expect(headings[1]?.markerRanges.map((range) => source.slice(range.from, range.to)))
      .toEqual(["============"]);
    expect(quote?.markerRanges.map((range) => source.slice(range.from, range.to)))
      .toEqual([">"]);
    expect(items.map((item) => ({
      depth: item.listDepth,
      parent: item.parent?.kind,
      markers: item.markerRanges.map((range) => source.slice(range.from, range.to)),
    }))).toEqual([
      {depth: 0, parent: "unorderedList", markers: ["-", "[x]"]},
      {depth: 1, parent: "unorderedList", markers: ["-"]},
    ]);
    expect(strong?.markerRanges.map((range) => source.slice(range.from, range.to)))
      .toEqual(["**", "**"]);
    expect(strong?.visibleRanges.map((range) => source.slice(range.from, range.to)))
      .toEqual(["strong"]);
    expect(link?.visibleRanges.map((range) => source.slice(range.from, range.to)))
      .toEqual(["link"]);
    expect(wikilink?.targetRange && source.slice(wikilink.targetRange.from, wikilink.targetRange.to))
      .toBe("Target Note");
    expect(wikilink?.aliasRange && source.slice(wikilink.aliasRange.from, wikilink.aliasRange.to))
      .toBe("Visible alias");
    expect(annotatedLink?.targetRange && source.slice(annotatedLink.targetRange.from, annotatedLink.targetRange.to))
      .toBe("Source Note");
    expect(annotatedLink?.annotationContentRange
      && source.slice(annotatedLink.annotationContentRange.from, annotatedLink.annotationContentRange.to))
      .toBe("A long annotation.");
    expect(annotatedLink?.to).toBe(annotatedLink?.annotationRange?.to);
  });

  it("maps the complete catalog through non-structural edits", () => {
    const source = "Paragraph with **strong**.";
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
    if (!tree) throw new Error("Expected the semantic syntax tree to complete.");
    const projection = semanticProjectionRanges(state, [{from: 0, to: source.length}], 0, tree);
    const transaction = state.update({changes: {from: 0, insert: "A "}});
    const mapped = mapSemanticProjectionRanges(
      projection,
      transaction.state,
      (position) => transaction.changes.mapPos(position),
    );

    const strong = mapped.inlines.find((inline) => inline.kind === "strong");
    expect(strong && transaction.state.doc.sliceString(strong.from, strong.to)).toBe("**strong**");
    expect(strong?.markerRanges.map((range) =>
      transaction.state.doc.sliceString(range.from, range.to))).toEqual(["**", "**"]);
  });
});

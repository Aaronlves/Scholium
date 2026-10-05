import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {
  boundedLinePrefix,
  boundedProjectionRanges,
  mapSemanticProjectionRanges,
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
  function completeProjection(source: string, visibleRanges = [{from: 0, to: source.length}]) {
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
    if (!tree) throw new Error("Expected the semantic syntax tree to complete.");
    return semanticProjectionRanges(state, visibleRanges, 0, tree);
  }

  it("resolves full, collapsed and shortcut image references to exact definition URLs", () => {
    const source = [
      "![Full *caption*][FIG URE]",
      "![Collapsed][]",
      "![Shortcut]",
      "",
      '[fig\ture]: <images/full.png> "Title"',
      "[collapsed]: images/collapsed.jpg",
      "[shortcut]: images/shortcut.webp",
    ].join("\n");
    const images = completeProjection(source).inlines.filter(inline => inline.kind === "image");

    expect(images.map(image => source.slice(image.from, image.to))).toEqual([
      "![Full *caption*][FIG URE]", "![Collapsed][]", "![Shortcut]",
    ]);
    expect(images.map(image => image.targetRange && source.slice(image.targetRange.from, image.targetRange.to)))
      .toEqual(["<images/full.png>", "images/collapsed.jpg", "images/shortcut.webp"]);
    expect(images.map(image => image.visibleRanges.map(range => source.slice(range.from, range.to))))
      .toEqual([["Full *caption*"], ["Collapsed"], ["Shortcut"]]);
    expect(images[0].markerRanges.map(range => source.slice(range.from, range.to))).toEqual(["![", "]"]);
  });

  it("matches raw reference labels with CommonMark case and whitespace normalization", () => {
    for (const [image, definition, destination] of [
      ["![alt][  FiG\nURE  ]", "[fig ure]: whitespace.png", "whitespace.png"],
      ["![ẞ]", "[SS]: unicode.png", "unicode.png"],
      ["![a\\]b]", "[a\\]b]: escaped.png", "escaped.png"],
      ["![a&amp;b]", "[a&amp;b]: entity.png", "entity.png"],
    ]) {
      const source = `${image}\n\n${definition}`;
      const resolved = completeProjection(source).inlines.find(inline => inline.kind === "image");
      expect(resolved?.targetRange && source.slice(resolved.targetRange.from, resolved.targetRange.to))
        .toBe(destination);
    }
    for (const source of [
      "![ı]\n\n[I]: dotless.png",
      "![a\\!b]\n\n[a!b]: escape.png",
      "![a&amp;b]\n\n[a&b]: entity.png",
      "![alt][fig\u00a0ure]\n\n[fig ure]: space.png",
    ]) {
      expect(completeProjection(source).inlines.filter(inline => inline.kind === "image")).toEqual([]);
    }
  });

  it("keeps the first reference destination authoritative without substituting a later local image", () => {
    const source = "![alt][figure]\n\n[FIGURE]: https://example.test/remote.png\n[figure]: local.png";
    const image = completeProjection(source).inlines.find(inline => inline.kind === "image");
    expect(image?.targetRange && source.slice(image.targetRange.from, image.targetRange.to))
      .toBe("https://example.test/remote.png");
  });

  it("leaves missing references and unfinished destinations as source", () => {
    for (const image of ["![missing][unknown]", "![missing][]", "![missing]",
      "![known](", "![known](unfinished", "![known]()", "![known][unfinished"]) {
      const source = `${image}\n\n[known]: admitted.png`;
      expect(completeProjection(source).inlines.filter(inline => inline.kind === "image")).toEqual([]);
    }
  });

  it("does not resolve image labels from reference lookalikes inside literals", () => {
    for (const definition of [
      "```markdown\n[hidden]: code.png\n```",
      "    [hidden]: indented.png",
      "%%\n[hidden]: comment.png\n%%",
      "<!--\n[hidden]: html.png\n-->",
      "---\ntitle: |\n  [hidden]: yaml.png\n---",
    ]) {
      const source = `${definition}\n\n![hidden]`;
      expect(completeProjection(source).inlines.filter(inline => inline.kind === "image")).toEqual([]);
    }
  });

  it("uses only an image's direct destination and alt markers", () => {
    const source = "![alt [nested](wrong.png)](right.png)";
    const image = completeProjection(source).inlines.find(inline => inline.kind === "image");
    expect(image?.targetRange && source.slice(image.targetRange.from, image.targetRange.to)).toBe("right.png");
    expect(image?.visibleRanges.map(range => source.slice(range.from, range.to))).toEqual(["alt [nested](wrong.png)"]);
    expect(image?.markerRanges.map(range => source.slice(range.from, range.to))).toEqual(["![", "]", "(", ")"]);
  });

  it("resolves definitions outside the projection viewport and maps their separate URL ranges", () => {
    const imageSource = "![caption][figure]";
    const source = `${imageSource}\n\n${"Distant paragraph.\n\n".repeat(250)}[figure]: images/photo.png`;
    const projection = completeProjection(source, [{from: 0, to: imageSource.length}]);
    const image = projection.inlines.find(inline => inline.kind === "image");
    expect(image?.targetRange && source.slice(image.targetRange.from, image.targetRange.to)).toBe("images/photo.png");
    expect(projection.blocks.every(block => block.from <= imageSource.length)).toBe(true);

    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    const transaction = state.update({changes: {from: 0, insert: "Prefix.\n\n"}});
    const mapped = mapSemanticProjectionRanges(projection, position => transaction.changes.mapPos(position, 1));
    const mappedImage = mapped.inlines.find(inline => inline.kind === "image");
    expect(mappedImage && transaction.state.doc.sliceString(mappedImage.from, mappedImage.to)).toBe(imageSource);
    expect(mappedImage?.targetRange && transaction.state.doc.sliceString(mappedImage.targetRange.from, mappedImage.targetRange.to))
      .toBe("images/photo.png");
    expect(transaction.state.doc.toString()).toBe(`Prefix.\n\n${source}`);
  });

  it("projects only paragraph identity suffixes outside protected syntax", () => {
    const source = "Paragraph. ^identity-1\n\n`code ^literal`\n\n```\nCode ^no\n```\n\n%% hidden ^no %%\n\nTrailing.";
    const ranges = completeProjection(source);
    const anchors = ranges.inlines.filter((inline) => inline.kind === "blockAnchor");
    expect(anchors.map((anchor) => source.slice(anchor.from, anchor.to))).toEqual(["^identity-1"]);
    expect(anchors[0].visibleRanges).toEqual([]);
    expect(anchors[0].markerRanges).toEqual([{from: source.indexOf("^identity-1"), to: source.indexOf("^identity-1") + 11}]);
    for (const protectedSource of ["- Listed ^no", "> Quoted ^no", "%%\n\nHidden ^no\n\n%%", "Math $x$ ^no", "Inline ^[note] ^no", "^orphan"]) {
      expect(completeProjection(protectedSource).inlines.filter((inline) => inline.kind === "blockAnchor")).toEqual([]);
    }
    const standalone = "Paragraph.\n\n^one\n\nNext.";
    expect(completeProjection(standalone).inlines.filter((inline) => inline.kind === "blockAnchor")
      .map((inline) => standalone.slice(inline.from, inline.to))).toEqual(["^one"]);
  });

  it("proves representative standard Markdown ranges", () => {
    const source = "## Claim\n\n**strong**, *emphasis*, and ==highlight== with [link](https://example.test).\n\n| A | B |\n|---|---|\n| 1 | 2 |";
    const ranges = completeProjection(source);
    const strongFrom = source.indexOf("**strong**");
    const emphasisFrom = source.indexOf("*emphasis*");
    const linkFrom = source.indexOf("[link]");
    const highlightFrom = source.indexOf("==highlight==");

    expect(ranges.blocks.find((block) => block.kind === "heading")?.headingLevel).toBe(2);
    expect(ranges.inlines.some((inline) =>
      inline.kind === "strong" && inline.from === strongFrom
        && inline.to === strongFrom + "**strong**".length)).toBe(true);
    expect(ranges.inlines.some((inline) =>
      inline.kind === "emphasis" && inline.from === emphasisFrom
        && inline.to === emphasisFrom + "*emphasis*".length)).toBe(true);
    expect(ranges.inlines.some((inline) =>
      inline.kind === "link" && inline.from === linkFrom
        && inline.to === linkFrom + "[link](https://example.test)".length)).toBe(true);
    expect(ranges.inlines.some((inline) =>
      inline.kind === "highlight" && inline.from === highlightFrom
        && inline.to === highlightFrom + "==highlight==".length)).toBe(true);
    expect(ranges.blocks.filter((block) => block.kind === "table")).toHaveLength(1);
  });

  it("projects the first H1 after closed frontmatter together with later headings", () => {
    const source = "---\ntitle: Fixture\n---\n# Document title\n\n## Section";
    const ranges = completeProjection(source);

    expect(ranges.blocks.find((block) => block.from === source.indexOf("# Document"))?.headingLevel).toBe(1);
    expect(ranges.blocks.find((block) => block.from === source.indexOf("## Section"))?.headingLevel).toBe(2);
  });

  it("does not project malformed markers as semantics", () => {
    const source = "##no heading\n**unfinished\n[broken](";
    const ranges = completeProjection(source);
    expect(ranges.blocks.some((block) => block.kind === "heading")).toBe(false);
    expect(ranges.inlines.some((inline) => inline.kind === "strong")).toBe(false);
    expect(ranges.inlines.some((inline) => inline.kind === "link")).toBe(false);
  });

  it("distinguishes semantic callout blocks from ordinary quotations", () => {
    const source = "> [!state]- Claim\n> Supported body.\n\n> Ordinary quotation.";
    const ranges = completeProjection(source);
    const calloutEnd = source.indexOf("\n\n");

    expect(ranges.blocks.filter((block) => block.kind === "callout")).toEqual([
      expect.objectContaining({from: 0, to: calloutEnd}),
    ]);
    expect(ranges.blocks.find((block) => block.kind === "callout")?.markerRanges
      .map((range) => source.slice(range.from, range.to))).toEqual([">", "[!state]-", ">"]);
  });

  it("uses the raw HTML projection for block comments", () => {
    const source = "<!-- inert source comment -->\n\n<section>Literal HTML.</section>";
    const ranges = completeProjection(source);
    const htmlBlocks = ranges.blocks.filter((block) => block.kind === "html");

    expect(htmlBlocks.map((block) => source.slice(block.from, block.to)))
      .toEqual(["<!-- inert source comment -->", "<section>Literal HTML.</section>"]);
    expect(ranges.literals.map((literal) => source.slice(literal.from, literal.to)))
      .toContain("<!-- inert source comment -->");
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
      (position) => transaction.changes.mapPos(position),
    );

    const strong = mapped.inlines.find((inline) => inline.kind === "strong");
    expect(strong && transaction.state.doc.sliceString(strong.from, strong.to)).toBe("**strong**");
    expect(strong?.markerRanges.map((range) =>
      transaction.state.doc.sliceString(range.from, range.to))).toEqual(["**", "**"]);
  });
});

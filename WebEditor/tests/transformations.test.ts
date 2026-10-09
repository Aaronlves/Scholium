import {describe, expect, it} from "vitest";
import {applySourceChanges, transformMarkdown} from "../transformations";
import {footnotePresentation} from "../footnote-presentation";
import {EditorState} from "@codemirror/state";
import {scholiumNoteLanguage} from "../language";
import {semanticProjectionRanges} from "../semantic-projection";

function apply(source: string, command: Parameters<typeof transformMarkdown>[2], from: number, to = from, argument?: string) {
  const result = transformMarkdown(source, [{anchor: from, head: to}], command, {argument});
  expect(result).not.toBeNull();
  return {result: result!, source: applySourceChanges(source, result!.changes)};
}

function headingMetadata(source: string) {
  const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
  return semanticProjectionRanges(state, [{from: 0, to: state.doc.length}], 0).blocks
    .filter(block => block.kind === "heading");
}

function transformSetext(source: string, command: Parameters<typeof transformMarkdown>[2], head: number, to = head) {
  return transformMarkdown(source, [{anchor: head, head: to}], command, {
    setextHeadings: headingMetadata(source).filter(block => block.nodeName.startsWith("SetextHeading")),
  });
}

describe("exact Markdown transformations", () => {
  it("leaves the next line outside a half-open block selection", () => {
    expect(apply("one\ntwo\nthree", "bulletList", 0, 4).source).toBe("- one\ntwo\nthree");
    expect(apply("\nsecond", "bulletList", 0, 1).source).toBe("- \nsecond");
    const source = "claim\n```js\nsecret\n```\n";
    const result = transformMarkdown(source, [{anchor: 0, head: 6}], "bulletList", {
      protectedRanges: [{from: 6, to: 22}],
    });
    expect(applySourceChanges(source, result!.changes)).toBe("- claim\n```js\nsecret\n```\n");
  });

  it("rejects a block edit whose expanded line includes protected text", () => {
    expect(transformMarkdown("prose $x$", [{anchor: 0, head: 4}], "bulletList", {
      protectedRanges: [{from: 6, to: 9}],
    })).toBeNull();
  });
  it("inserts a document link into the current selection with one undo transaction", () => {
    const {result, source} = apply("Before selected after", "insertAttachment", 7, 15,
      JSON.stringify({alt: "Paper [draft].pdf", destination: "../Attachments/id/Paper%20%5Bdraft%5D.pdf"}));
    expect(source).toBe("Before [selected](../Attachments/id/Paper%20%5Bdraft%5D.pdf) after");
    expect(result.undoLabel).toBe("Insert Attachment");
  });

  it("inserts a validated relative Markdown image link in one transaction", () => {
    const argument = JSON.stringify({
      alt: "Figure [one]",
      destination: "../Attachments/id/Figure%201.png",
    });
    const result = transformMarkdown(
      "Before ",
      [{anchor: 7, head: 7}],
      "insertImage",
      {argument},
    );
    expect(result).not.toBeNull();
    expect(applySourceChanges("Before ", result!.changes))
      .toBe("Before ![Figure \\[one\\]](../Attachments/id/Figure%201.png)");
    expect(result!.undoLabel).toBe("Insert Image");
  });

  it("rejects unsafe image destinations", () => {
    for (const destination of [
      "https://example.com/image.png",
      "bad%2.png",
      "bad image.png",
      "/Users/researcher/../image.png",
    ]) {
      expect(transformMarkdown("", [{anchor: 0, head: 0}], "insertImage", {
        argument: JSON.stringify({alt: "Image", destination}),
      })).toBeNull();
    }
  });

  it("accepts a percent-encoded absolute path for an indexed image", () => {
    const result = transformMarkdown("", [{anchor: 0, head: 0}], "insertImage", {
      argument: JSON.stringify({
        alt: "External figure",
        destination: "/Users/researcher/Figures/Figure%201.png",
      }),
    });
    expect(result).not.toBeNull();
    expect(applySourceChanges("", result!.changes))
      .toBe("![External figure](/Users/researcher/Figures/Figure%201.png)");
  });

  it("implements the closed inline command vocabulary exactly", () => {
    const cases = [
      ["bold", "**claim**"], ["emphasis", "*claim*"], ["strikethrough", "~~claim~~"],
      ["highlight", "==claim=="], ["inlineCode", "`claim`"], ["wikilink", "[[claim]]"],
      ["annotatedWikilink", "[[claim]]{{Annotation}}"],
      ["markdownComment", "%% claim %%"],
    ] as const;
    for (const [command, expected] of cases) expect(apply("claim", command, 0, 5).source).toBe(expected);
  });
  it("selects the annotation placeholder after annotating a selected target", () => {
    const transformed = apply("claim", "annotatedWikilink", 0, 5);
    expect(transformed.result.selections).toEqual([{anchor: 11, head: 21}]);
  });
  it("wraps and unwraps only the selected range", () => {
    expect(apply("before thesis after", "bold", 7, 13).source).toBe("before **thesis** after");
    expect(apply("before **thesis** after", "bold", 9, 15).source).toBe("before thesis after");
  });
  it("wraps a multiline Obsidian comment without touching adjacent bytes", () => {
    expect(apply("before\nfirst\nsecond\nafter", "markdownComment", 7, 19).source).toBe(
      "before\n%% first\nsecond %%\nafter",
    );
  });
  it("uses a safe inline and fenced-code delimiter", () => {
    expect(apply("a`b", "inlineCode", 0, 3).source).toBe("``a`b``");
    expect(apply("x\n```\ny", "fencedCode", 0, 7).source).toBe("````\nx\n```\ny\n````");
  });
  it.each([
    ["`literal", "`` `literal ``", 3],
    ["literal`", "`` literal` ``", 3],
    [" a b ", "`  a b  `", 2],
    ["   ", "`   `", 1],
    [" \n ", "` \n `", 1],
  ])("keeps inline-code boundary content exact for %j", (text, expected, offset) => {
    const transformed = apply(text, "inlineCode", 0, text.length);
    expect(transformed.source).toBe(expected);
    expect(transformed.result.selections).toEqual([{anchor: offset, head: offset + text.length}]);
    expect(apply(expected, "inlineCode", offset, offset + text.length).source).toBe(text);
  });
  it("changes only proven ATX heading markers", () => {
    expect(apply("  ## Thesis\nNext", "heading4", 6).source).toBe("#### Thesis\nNext");
    expect(apply("#### Thesis\nNext", "paragraph", 6).source).toBe("Thesis\nNext");
  });
  it.each(["Title\n=====", "First line\nSecond line\n==========="])("turns a parsed Setext heading into a paragraph without losing content: %j", title => {
    const source = `Before 😀 é.\n\n${title}\n\nAfter.`;
    const titleFrom = source.indexOf(title);
    const result = transformSetext(source, "paragraph", source.indexOf("="))!;
    const changed = applySourceChanges(source, result.changes);
    const content = title.slice(0, title.lastIndexOf("\n"));
    expect(changed).toBe(`Before 😀 é.\n\n${content}\n\nAfter.`);
    expect(headingMetadata(changed)).toHaveLength(0);
    expect(changed.slice(result.selections[0].anchor, result.selections[0].head)).toBe(content);
    expect(result.changes[0].from).toBe(titleFrom);
  });
  it.each([1, 2])("changes multiline Setext titles to level %s by editing only the parser marker", level => {
    const source = "Before.\n\nFirst line\nSecond line\n=========\n\nAfter.";
    const command = level === 1 ? "heading1" : "heading2";
    const result = transformSetext(source, command, source.indexOf("Second"))!;
    const changed = applySourceChanges(source, result.changes);
    expect(changed).toBe(source.replace("=========", (level === 1 ? "=" : "-").repeat(9)));
    expect(headingMetadata(changed).map(heading => heading.nodeName)).toEqual([`SetextHeading${level}`]);
  });
  it.each([3, 4, 5, 6])("converts one multiline Setext title into one ATX heading at level %s", level => {
    const source = "Before.\n\nFirst line\nSecond line\n=========\n\nAfter.";
    const result = transformSetext(source, `heading${level}` as Parameters<typeof transformMarkdown>[2], source.indexOf("="))!;
    const changed = applySourceChanges(source, result.changes);
    expect(changed).toBe(`Before.\n\n${"#".repeat(level)} First line Second line\n\nAfter.`);
    const headings = headingMetadata(changed);
    expect(headings.map(heading => heading.nodeName)).toEqual([`ATXHeading${level}`]);
    expect(changed.slice(result.selections[0].anchor, result.selections[0].head)).toBe("First line Second line");
  });
  it("converts distinct adjacent Setext selections atomically without swallowing neighboring bytes", () => {
    const source = "One\n===\n\nTwo\n---\n\nAfter.";
    const selections = [{anchor: 0, head: 3}, {anchor: source.indexOf("Two"), head: source.indexOf("Two") + 3}];
    const result = transformMarkdown(source, selections, "heading4", {
      setextHeadings: headingMetadata(source).filter(block => block.nodeName.startsWith("SetextHeading")),
    })!;
    const changed = applySourceChanges(source, result.changes);
    expect(changed).toBe("#### One\n\n#### Two\n\nAfter.");
    expect(result.selections.map(range => changed.slice(range.anchor, range.head))).toEqual(["One", "Two"]);
    expect(headingMetadata(changed).map(heading => heading.nodeName)).toEqual(["ATXHeading4", "ATXHeading4"]);
    expect(transformSetext(source, "paragraph", 0, source.indexOf("After"))).toBeNull();
  });
  it.each(["> Title\n> =====", "- Title\n  ====="])("declines container-owned Setext syntax without changing its source: %j", source => {
    expect(headingMetadata(source).some(block => block.nodeName.startsWith("SetextHeading"))).toBe(true);
    expect(transformSetext(source, "heading3", source.indexOf("Title"))).toBeNull();
    expect(transformSetext(source, "paragraph", source.indexOf("="))).toBeNull();
  });
  it("applies multiple selections atomically and maps selections", () => {
    const result = transformMarkdown("one two three", [{anchor: 0, head: 3}, {anchor: 8, head: 13}], "emphasis");
    expect(result).not.toBeNull();
    expect(applySourceChanges("one two three", result!.changes)).toBe("*one* two *three*");
    expect(result!.selections).toEqual([{anchor: 1, head: 4}, {anchor: 11, head: 16}]);
  });
  it("refuses every selection when one intersects a protected range", () => {
    expect(transformMarkdown("front body", [{anchor: 0, head: 5}, {anchor: 6, head: 10}], "bold", {
      protectedRanges: [{from: 0, to: 5}],
    })).toBeNull();
    expect(transformMarkdown("---\ntitle: exact\n---\n", [{anchor: 0, head: 0}], "bold", {
      protectedRanges: [{from: 0, to: 20}],
    })).toBeNull();
  });
  it("does not unwrap escaped delimiters or emit overlapping line edits", () => {
    expect(apply("\\**literal**", "bold", 1, 12).source).toBe("\\****literal****");
    expect(transformMarkdown("one line", [{anchor: 0, head: 3}, {anchor: 4, head: 8}], "heading2")).toBeNull();
  });
  it.each([2, 4])("unwraps real delimiters preceded by %s literal backslashes", count => {
    const prefix = "\\".repeat(count);
    const source = `${prefix}**word**`;
    expect(apply(source, "bold", prefix.length, source.length).source).toBe(`${prefix}word`);
    expect(apply(source, "bold", prefix.length + 2, source.length - 2).source).toBe(`${prefix}word`);
  });
  it.each([
    ["`word`", "word"], ["`` a`b ``", "a`b"], ["`` `literal ``", "`literal"], ["`   `", "   "],
  ])("unwraps a completely selected code span %j without retaining padding", (source, expected) => {
    expect(apply(source, "inlineCode", 0, source.length).source).toBe(expected);
  });
  it("does not mistake separate or unmatched code spans for one enclosing span", () => {
    for (const source of ["`one` and `two`", "```unmatched``"]) {
      const result = apply(source, "inlineCode", 0, source.length);
      const selection = result.result.selections[0];
      expect(result.source.slice(selection.anchor, selection.head)).toBe(source);
    }
  });
  it("inserts exact links, callouts, and a bounded table", () => {
    expect(apply("claim", "standardLink", 0, 5, "https://example.test").source).toBe("[claim](https://example.test)");
    expect(apply("Scope", "calloutOrient", 0, 5).source).toBe("> [!orient] Scope");
    expect(apply("", "insertTable", 0).source).toBe("| Column 1 | Column 2 |\n|---|---|\n|  |  |");
  });
  it("uses canonical exact block prefixes", () => {
    const cases = [
      ["blockQuotation", "> Claim"], ["bulletList", "- Claim"], ["numberedList", "1. Claim"],
      ["taskList", "- [ ] Claim"], ["calloutCite", "> [!cite] Claim"],
      ["calloutConnect", "> [!connect] Claim"], ["calloutState", "> [!state] Claim"],
      ["calloutIllustrate", "> [!illustrate] Claim"], ["calloutQuote", "> [!quote] Claim"],
      ["calloutFlag", "> [!flag] Claim"],
    ] as const;
    for (const [command, expected] of cases) expect(apply("Claim", command, 0, 5).source).toBe(expected);
  });
  it("preserves CRLF, BOM, YAML, and final-newline bytes outside edits", () => {
    const source = "\uFEFF---\r\ntitle: Exact\r\n---\r\nBody\r\n";
    const from = source.indexOf("Body");
    const result = apply(source, "bold", from, from + 4).source;
    expect(result).toBe("\uFEFF---\r\ntitle: Exact\r\n---\r\n**Body**\r\n");
  });
  it("allocates footnotes without renumbering existing definitions", () => {
    const source = "First and second.[^2]\n\n[^2]: Existing\n";
    const result = transformMarkdown(source, [{anchor: 0, head: 5}], "insertFootnote");
    expect(result).not.toBeNull();
    expect(applySourceChanges(source, result!.changes)).toBe(
      "[^1] and second.[^2]\n\n[^2]: Existing\n\n[^1]: First\n",
    );
  });
  it("keeps every selected paragraph inside the newly inserted footnote", () => {
    const content = "First line\nSecond line\n\n- Nested item\n  continuation";
    const source = `${content}\n\nFollowing prose.`;
    const result = transformMarkdown(source, [{anchor: 0, head: content.length}], "insertFootnote")!;
    const changed = applySourceChanges(source, result.changes);
    expect(changed).toBe("[^1]\n\nFollowing prose.\n\n[^1]: First line\n  Second line\n  \n  - Nested item\n    continuation\n");
    const presentation = footnotePresentation(changed);
    expect(presentation.definitions).toHaveLength(1);
    expect(presentation.definitions[0].content).toBe(content);
    expect(changed.slice(result.selections[0].anchor, result.selections[0].head))
      .toBe(content.replaceAll("\n", "\n  "));
  });
  it.each(["", "Text", "Text\n"])("inserts a resolvable footnote at the end of %j", source => {
    const head = source.length;
    const result = transformMarkdown(source, [{anchor: head, head}], "insertFootnote")!;
    const changed = EditorState.create({doc: source}).update({changes: result.changes}).newDoc.toString();
    expect(applySourceChanges(source, result.changes)).toBe(changed);
    const projection = footnotePresentation(changed);
    expect(projection.definitions).toHaveLength(1);
    expect(projection.references).toHaveLength(1);
    expect(projection.references[0].definitionFrom).toBe(projection.definitions[0].from);
    expect(result.selections[0].head).toBe(projection.definitions[0].contentFrom);
  });
  it("inserts inline footnotes at one or several exact selections", () => {
    const empty = transformMarkdown("Claim.", [{anchor: 5, head: 5}], "insertInlineFootnote");
    expect(empty).not.toBeNull();
    expect(applySourceChanges("Claim.", empty!.changes)).toBe("Claim^[].");
    expect(empty!.selections).toEqual([{anchor: 7, head: 7}]);
    expect(empty!.undoLabel).toBe("Insert Inline Footnote");

    const source = "First and second";
    const selected = transformMarkdown(source, [
      {anchor: 0, head: 5},
      {anchor: 10, head: 16},
    ], "insertInlineFootnote");
    expect(selected).not.toBeNull();
    expect(applySourceChanges(source, selected!.changes))
      .toBe("^[First] and ^[second]");
    expect(selected!.selections).toEqual([
      {anchor: 2, head: 7},
      {anchor: 15, head: 21},
    ]);
  });
  it("toggles only the three task-marker bytes", () => {
    expect(apply("- [ ] exact task", "toggleTask", 8).source).toBe("- [x] exact task");
    expect(apply("- [x] exact task", "toggleTask", 8).source).toBe("- [ ] exact task");
    expect(apply("- [X] exact task", "toggleTask", 8).source).toBe("- [ ] exact task");
    expect(apply("* [ ] alternate task", "toggleTask", 8).source).toBe("* [x] alternate task");
    expect(apply("+ [x] alternate task", "toggleTask", 8).source).toBe("+ [ ] alternate task");
    expect(apply("12. [ ] ordered task", "toggleTask", 10).source).toBe("12. [x] ordered task");
  });

  it("uses one indexed marker for continuation carets and duplicate selections", () => {
    const source = "- [ ] task body\n  continued body";
    const continuation = source.indexOf("continued") + 4;
    const result = transformMarkdown(source, [
      {anchor: continuation, head: continuation},
      {anchor: continuation + 2, head: continuation + 2},
    ], "toggleTask", {
      taskItems: [{from: 0, to: source.length, markerFrom: 2, markerTo: 5}],
    });

    expect(result?.changes).toEqual([{from: 2, to: 5, insert: "[x]"}]);
    expect(applySourceChanges(source, result!.changes))
      .toBe("- [x] task body\n  continued body");
  });

  it("orders distinct parent and child task changes by exact source position", () => {
    const source = [
      "- [ ] parent",
      "  - [ ] child",
      "  parent continuation",
    ].join("\n");
    const parentMarker = source.indexOf("[ ]");
    const childMarker = source.indexOf("[ ]", parentMarker + 3);
    const childFrom = source.indexOf("  - [ ] child");
    const childTo = source.indexOf("\n", childFrom);
    const childCaret = source.indexOf("child") + 2;
    const parentCaret = source.indexOf("parent continuation") + 2;
    const result = transformMarkdown(source, [
      {anchor: childCaret, head: childCaret},
      {anchor: parentCaret, head: parentCaret},
    ], "toggleTask", {
      taskItems: [
        {from: 0, to: source.length, markerFrom: parentMarker, markerTo: parentMarker + 3},
        {from: childFrom, to: childTo, markerFrom: childMarker, markerTo: childMarker + 3},
      ],
    });

    expect(result?.changes).toEqual([
      {from: parentMarker, to: parentMarker + 3, insert: "[x]"},
      {from: childMarker, to: childMarker + 3, insert: "[x]"},
    ]);
  });
});

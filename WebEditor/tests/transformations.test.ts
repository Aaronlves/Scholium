import {describe, expect, it} from "vitest";
import {applySourceChanges, transformMarkdown} from "../transformations";

function apply(source: string, command: Parameters<typeof transformMarkdown>[2], from: number, to = from, argument?: string) {
  const result = transformMarkdown(source, [{anchor: from, head: to}], command, {argument});
  expect(result).not.toBeNull();
  return {result: result!, source: applySourceChanges(source, result!.changes)};
}

describe("exact Markdown transformations", () => {
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
  it("changes only proven ATX heading markers", () => {
    expect(apply("  ## Thesis\nNext", "heading4", 6).source).toBe("#### Thesis\nNext");
    expect(apply("#### Thesis\nNext", "paragraph", 6).source).toBe("Thesis\nNext");
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

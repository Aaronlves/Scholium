import {describe, expect, it} from "vitest";
import {applySourceChanges, transformMarkdown} from "../transformations";

function apply(source: string, command: Parameters<typeof transformMarkdown>[2], from: number, to = from, argument?: string) {
  const result = transformMarkdown(source, [{anchor: from, head: to}], command, {argument});
  expect(result).not.toBeNull();
  return {result: result!, source: applySourceChanges(source, result!.changes)};
}

describe("exact Markdown transformations", () => {
  it("implements the closed inline command vocabulary exactly", () => {
    const cases = [
      ["bold", "**claim**"], ["emphasis", "*claim*"], ["strikethrough", "~~claim~~"],
      ["highlight", "==claim=="], ["inlineCode", "`claim`"], ["wikilink", "[[claim]]"],
      ["vectorSupports", "+[[claim]]"], ["vectorOpposes", "-[[claim]]"],
      ["vectorIncompatible", "?[[claim]]"], ["markdownComment", "%% claim %%"],
    ] as const;
    for (const [command, expected] of cases) expect(apply("claim", command, 0, 5).source).toBe(expected);
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
  });
});

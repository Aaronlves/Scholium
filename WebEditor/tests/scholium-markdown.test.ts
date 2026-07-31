import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {scholiumNoteLanguage} from "../language";

interface LocatedNode {name: string; from: number; to: number; source: string}

function locatedNodes(source: string) {
  const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
  const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
  if (!tree) throw new Error("Expected the Scholium syntax tree to complete.");
  const result: LocatedNode[] = [];
  tree.iterate({
    enter(node) {
      result.push({name: node.name, from: node.from, to: node.to, source: source.slice(node.from, node.to)});
    },
  });
  return result;
}

function sources(nodes: LocatedNode[], name: string) {
  return nodes.filter((node) => node.name === name).map((node) => node.source);
}

describe("Scholium Lezer Markdown dialect", () => {
  it("locates wiki, vector, alias, fragment, and embed source exactly", () => {
    const source = "[[Note]] +[[A#Claim|support]] -[[B]] ?[[C^block]] ![[Figure]] C++[[Adjacent]] \\+[[Escaped]]";
    const nodes = locatedNodes(source);
    expect(sources(nodes, "WikiLink")).toEqual([
      "[[Note]]", "![[Figure]]", "[[Adjacent]]", "[[Escaped]]",
    ]);
    expect(sources(nodes, "VectorLink")).toEqual([
      "+[[A#Claim|support]]", "-[[B]]", "?[[C^block]]",
    ]);
    expect(sources(nodes, "WikiLinkTarget")).toEqual([
      "Note", "A#Claim", "B", "C^block", "Figure", "Adjacent", "Escaped",
    ]);
    expect(sources(nodes, "WikiLinkAlias")).toEqual(["support"]);
  });

  it("locates named, inline, and multiline definition footnotes", () => {
    const source = "Claim[^N] and ^[inline note].\n\n[^N]: first line\n  continuation\n\nAfter.";
    const nodes = locatedNodes(source);
    expect(sources(nodes, "FootnoteReference")).toEqual(["[^N]"]);
    expect(sources(nodes, "InlineFootnote")).toEqual(["^[inline note]"]);
    expect(sources(nodes, "FootnoteDefinition")).toEqual(["[^N]: first line\n  continuation"]);
    expect(sources(nodes, "FootnoteIdentifier")).toEqual(["N", "N"]);
  });

  it("keeps a structured multiline footnote in one exact block node", () => {
    const source = "Claim[^blocks].\n\n[^blocks]: First paragraph.\n\n  - Outer item\n    - Nested item\n\n  ```swift\n  let value = 1\n  ```\nFollowing.";
    const nodes = locatedNodes(source);
    expect(sources(nodes, "FootnoteDefinition")).toEqual([
      "[^blocks]: First paragraph.\n\n  - Outer item\n    - Nested item\n\n  ```swift\n  let value = 1\n  ```",
    ]);
    expect(sources(nodes, "BulletList").some((value) => value.includes("Outer item"))).toBe(true);
    expect(sources(nodes, "ListItem").some((value) => value.includes("Nested item"))).toBe(true);
    expect(sources(nodes, "FencedCode").some((value) => value.includes("let value = 1"))).toBe(true);
  });

  it("starts an adjacent named footnote definition after a continuation", () => {
    const source = "[^reason]: First line\n  second line\n[^unused]: Not cited.\n";
    expect(sources(locatedNodes(source), "FootnoteDefinition")).toEqual([
      "[^reason]: First line\n  second line",
      "[^unused]: Not cited.",
    ]);
  });

  it("locates inline, display, unclosed mathematics, and callouts", () => {
    const source = "$x + y$ and ==important==\n\n$$\na^2 + b^2\n$$\n\n> [!theorem] Claim\n> body\n\n$$\nunclosed";
    const nodes = locatedNodes(source);
    expect(sources(nodes, "InlineMath")).toEqual(["$x + y$"]);
    expect(sources(nodes, "Highlight")).toEqual(["==important=="]);
    expect(sources(nodes, "BlockMath")).toEqual(["$$\na^2 + b^2\n$$"]);
    expect(sources(nodes, "Callout")).toEqual(["> [!theorem] Claim\n> body"]);
    expect(sources(nodes, "UnclosedBlockMath")).toEqual(["$$\nunclosed"]);
  });

  it("excludes YAML, code, HTML comments, Obsidian comments, and escapes", () => {
    const source = [
      "---", "value: '[[yaml]] $yaml$ [^yaml]'", "---",
      "`[[code]] $code$ [^code]`",
      "```md", "+[[fenced]] $fenced$ [^fenced]", "```",
      "<!-- [[html]] $html$ [^html] -->",
      "%% [[comment]] $comment$ [^comment] %%",
      "Text %% [[inline-comment]] $inline$ [^inline] %% after.",
      "\\[[escaped]] \\$escaped$ \\[^escaped]",
      "[[visible]] $visible$ [^visible]",
    ].join("\n");
    const nodes = locatedNodes(source);
    expect(sources(nodes, "WikiLink")).toEqual(["[[visible]]"]);
    expect(sources(nodes, "VectorLink")).toEqual([]);
    expect(sources(nodes, "InlineMath")).toEqual(["$visible$"]);
    expect(sources(nodes, "FootnoteReference")).toEqual(["[^visible]"]);
    expect(sources(nodes, "ObsidianCommentBlock")).toEqual(["%% [[comment]] $comment$ [^comment] %%"]);
    expect(sources(nodes, "ObsidianComment")).toEqual(["%% [[inline-comment]] $inline$ [^inline] %%"]);
  });

  it("keeps multiline and unclosed Obsidian comments as literal blocks", () => {
    const closed = "%%\n[[hidden]] $hidden$ [^hidden]\n\n> [!flag] hidden\n%%\n\n[[visible]]";
    const closedNodes = locatedNodes(closed);
    expect(sources(closedNodes, "ObsidianCommentBlock")).toEqual([
      "%%\n[[hidden]] $hidden$ [^hidden]\n\n> [!flag] hidden\n%%",
    ]);
    expect(sources(closedNodes, "WikiLink")).toEqual(["[[visible]]"]);
    expect(sources(closedNodes, "InlineMath")).toEqual([]);
    expect(sources(closedNodes, "FootnoteReference")).toEqual([]);
    expect(sources(closedNodes, "Callout")).toEqual([]);

    const unclosedNodes = locatedNodes("%%\n[[hidden]]\n\n$hidden$");
    expect(sources(unclosedNodes, "UnclosedObsidianCommentBlock")).toEqual([
      "%%\n[[hidden]]\n\n$hidden$",
    ]);
    expect(sources(unclosedNodes, "WikiLink")).toEqual([]);
    expect(sources(unclosedNodes, "InlineMath")).toEqual([]);
  });
});

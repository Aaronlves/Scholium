import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {scholiumNoteLanguage} from "../language";

function namesFor(source: string) {
  const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
  const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
  if (!tree) throw new Error("Expected the note syntax tree to complete.");
  const names: string[] = [];
  tree.iterate({enter: (node) => { names.push(node.name); }});
  return names;
}

describe("complete note-language coverage", () => {
  it("keeps the mature CommonMark/GFM nodes beside Scholium nodes", () => {
    const source = [
      "# H1", "## H2", "### H3", "#### H4", "##### H5", "###### H6", "",
      "Paragraph with **strong**, *emphasis*, ~~strike~~, ==highlight==, `code`, and [link](https://example.test).", "",
      "- bullet", "- [x] task", "", "1. ordered", "", "> quotation", "",
      "| A | B |", "|:--|--:|", "| 1 | 2 |", "",
      "```swift", "let value = 1", "```", "", "---",
    ].join("\n");
    const names = namesFor(source);
    for (let level = 1; level <= 6; level += 1) expect(names).toContain(`ATXHeading${level}`);
    for (const name of [
      "Paragraph", "StrongEmphasis", "Emphasis", "Strikethrough", "Highlight", "InlineCode", "Link",
      "BulletList", "OrderedList", "Task", "Blockquote", "Table", "FencedCode", "HorizontalRule",
    ]) expect(names).toContain(name);
  });

  it("preserves nested callouts and leaves incomplete inline constructs untyped", () => {
    const source = [
      "> [!orient] Outer", "> body", ">", "> > [!flag] Nested", "> > warning", "",
      "[[unfinished and ==unfinished and $unfinished",
    ].join("\n");
    const names = namesFor(source);
    expect(names.filter((name) => name === "Callout")).toHaveLength(2);
    expect(names).not.toContain("WikiLink");
    expect(names).not.toContain("Highlight");
    expect(names).not.toContain("InlineMath");
  });

  it("keeps the complete incomplete-marker catalog as ordinary editable source", () => {
    const names = namesFor([
      "[^unclosed", "[^]: empty identifier", "^[unclosed", "^[]", "[[unclosed",
      "==unclosed", "$unclosed", "> [!unclosed",
    ].join("\n"));
    for (const name of [
      "FootnoteReference", "FootnoteDefinition", "InlineFootnote", "WikiLink", "VectorLink",
      "Highlight", "InlineMath", "Callout",
    ]) expect(names).not.toContain(name);
  });

  it("types only structurally unclosed block constructs for fail-closed diagnostics", () => {
    expect(namesFor("$$\nx + y")).toContain("UnclosedBlockMath");
    expect(namesFor("%%\nhidden")).toContain("UnclosedObsidianCommentBlock");
  });
});

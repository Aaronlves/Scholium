import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {NodeProp} from "@lezer/common";
import {describe, expect, it} from "vitest";
import {scholiumNoteLanguage} from "../language";

function nodeNames(source: string) {
  const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
  const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
  if (!tree) throw new Error("Expected the note syntax tree to complete.");
  const names: string[] = [];
  tree.iterate({enter: (node) => { names.push(node.name); }});
  return names;
}

function nodeIsolates(source: string) {
  const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
  const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
  if (!tree) throw new Error("Expected the note syntax tree to complete.");
  const isolates = new Map<string, string>();
  tree.iterate({enter: (node) => {
    const direction = node.type.prop(NodeProp.isolate);
    if (direction) isolates.set(node.name, direction);
  }});
  return isolates;
}

describe("Scholium note language", () => {
  it("parses YAML frontmatter and Markdown body through one incremental tree", () => {
    const names = nodeNames("---\ntitle: Scope\n---\n# Claim\n");
    expect(names).toContain("Frontmatter");
    expect(names).toContain("BlockMapping");
    expect(names).toContain("ATXHeading1");
  });

  it("keeps malformed closed YAML inside the frontmatter boundary", () => {
    const names = nodeNames("---\ninvalid: [\n---\nParagraph.\n");
    expect(names).toContain("Frontmatter");
    expect(names).toContain("FlowSequence");
    expect(names).toContain("Paragraph");
  });

  it("does not classify an ordinary thematic break as frontmatter", () => {
    const names = nodeNames("Paragraph.\n\n---\n");
    expect(names).not.toContain("Frontmatter");
    expect(names).toContain("HorizontalRule");
  });

  it("owns bidi-isolation metadata for complete Markdown syntax constructs", () => {
    const isolates = nodeIsolates([
      "**دليل** *مصطلح* ~~مسحوب~~ ==مؤقت== `code()`",
      "[مرجع](https://example.test) [[Target|عارض]] +[[Support|داعم]]",
      "^[ملاحظة] [^note] $x^2$",
    ].join("\n\n"));

    for (const name of [
      "StrongEmphasis", "Emphasis", "Strikethrough", "Highlight", "InlineFootnote",
    ]) expect(isolates.get(name)).toBe("auto");
    for (const name of [
      "InlineCode", "InlineMath", "Link", "WikiLink", "VectorLink", "FootnoteReference",
    ]) expect(isolates.get(name)).toBe("ltr");
  });
});

import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
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
});

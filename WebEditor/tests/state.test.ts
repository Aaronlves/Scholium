import {Text} from "@codemirror/state";
import {describe, expect, it} from "vitest";
import {
  frontmatterBodyOffset,
  frontmatterBoundary,
  frontmatterEndLine,
  hasUnclosedFrontmatter,
} from "../state";

function documentText(source: string) {
  return Text.of(source.replaceAll("\r\n", "\n").split("\n"));
}

describe("frontmatter boundary", () => {
  it("recognizes closed LF, CRLF, and BOM frontmatter", () => {
    for (const source of [
      "---\ntitle: Scope\n---\nBody\n",
      "---\r\ntitle: Scope\r\n---\r\nBody\r\n",
      "\uFEFF---\ntitle: Scope\n---\nBody\n",
    ]) {
      const doc = documentText(source);
      expect(frontmatterBoundary(doc)).toEqual({endLine: 3, unclosed: false});
      expect(frontmatterEndLine(doc)).toBe(3);
      expect(frontmatterBodyOffset(doc)).toBe(doc.line(4).from);
      expect(hasUnclosedFrontmatter(doc)).toBe(false);
    }
  });

  it("fails closed when an opening delimiter has no closing delimiter", () => {
    const doc = documentText("---\ntitle: Scope\nBody\n");
    expect(frontmatterBoundary(doc)).toEqual({endLine: 0, unclosed: true});
    expect(hasUnclosedFrontmatter(doc)).toBe(true);
  });

  it("does not claim an ordinary thematic break or single delimiter line", () => {
    expect(frontmatterBoundary(documentText("Paragraph.\n\n---\n")))
      .toEqual({endLine: 0, unclosed: false});
    expect(frontmatterBoundary(documentText("---")))
      .toEqual({endLine: 0, unclosed: false});
  });

  it("owns the closing-delimiter newline and handles YAML-only source", () => {
    const withBody = documentText("---\ntitle: Note\n---\n# Body");
    expect(withBody.sliceString(0, frontmatterBodyOffset(withBody)))
      .toBe("---\ntitle: Note\n---\n");

    const yamlOnly = documentText("---\ntitle: Note\n---");
    expect(frontmatterBodyOffset(yamlOnly)).toBe(yamlOnly.length);
  });
});

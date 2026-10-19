import {describe, expect, it} from "vitest";
import {linkTargetAt} from "../link-target";
import {Text} from "@codemirror/state";

describe("exact link activation projection", () => {
  it("resolves Wikilink, annotated Wikilink, embed, and standard-link targets", () => {
    const source = "[[Note|Label]] ![[Figure#Block|Alias]] [[Support]]{{Reason.}} [Web](https://example.test)";
    expect(linkTargetAt(source, 4)).toBe("Note");
    expect(linkTargetAt(source, source.indexOf("!"))).toBe("Figure#Block");
    expect(linkTargetAt(source, source.indexOf("Support"))).toBe("Support");
    expect(linkTargetAt(source, source.indexOf("Web"))).toBe("https://example.test");
    expect(linkTargetAt("[[<Note>]]", 4)).toBe("<Note>");
  });
  it("uses a half-open activation boundary", () => {
    const source = "[[Note]] adjacent";
    expect(linkTargetAt(source, "[[Note]]".length - 1)).toBe("Note");
    expect(linkTargetAt(source, "[[Note]]".length)).toBeNull();
  });
  it("does not activate ordinary prose", () => {
    expect(linkTargetAt("plain claim", 3)).toBeNull();
  });
  it("resolves the clicked line directly from CodeMirror Text", () => {
    const source = "Earlier prose.\n[[Local target]]\nFollowing prose.";
    const document = Text.of(source.split("\n"));
    expect(linkTargetAt(document, source.indexOf("Local"))).toBe("Local target");
  });
  it.each([
    "/Users/fixture/Zotero/storage/TEST/Star - 2018 - The Oxford handbook of reasons and normativity.pdf",
    "/Users/fixture/原文/规范理由 (2018).pdf",
  ])("removes source angle delimiters from a PDF path with spaces: %s", path => {
    const source = `> 所读书目原文：[PDF](<${path}>)`;
    expect(linkTargetAt(Text.of(source.split("\n")), source.indexOf("PDF"))).toBe(path);
    expect(linkTargetAt(source, source.length)).toBeNull();
  });
  it("uses the parser's URL boundary for nested labels, parentheses and titles", () => {
    const source = '[Read **PDF**](<../原文/Reasons (2018).pdf> "Original PDF")';
    expect(linkTargetAt(source, source.indexOf("PDF"))).toBe("../原文/Reasons (2018).pdf");
    expect(linkTargetAt("[Web](https://example.test/a_(b))", 2)).toBe("https://example.test/a_(b)");
  });
  it("keeps citation fields and inline code out of ordinary link activation", () => {
    expect(linkTargetAt("`[PDF](</fixture/Original.pdf>)`", 3)).toBeNull();
    expect(linkTargetAt("`[[Note]]`", 4)).toBeNull();
    expect(linkTargetAt("[Citation](scholium-zotero:test)", 2)).toBeNull();
    expect(linkTargetAt("[Citation](cite:test)", 2)).toBeNull();
  });
});

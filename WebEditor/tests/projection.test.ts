import {describe, expect, it} from "vitest";
import {linkTargetAt} from "../projection";
import {Text} from "@codemirror/state";

describe("exact link activation projection", () => {
  it("resolves wikilink, embed, vector-link, and standard-link targets", () => {
    const source = "[[Note|Label]] ![[Figure#Block|Alias]] +[[Support]] [Web](https://example.test)";
    expect(linkTargetAt(source, 4)).toBe("Note");
    expect(linkTargetAt(source, source.indexOf("!"))).toBe("Figure#Block");
    expect(linkTargetAt(source, source.indexOf("Support"))).toBe("Support");
    expect(linkTargetAt(source, source.indexOf("Web"))).toBe("https://example.test");
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
});

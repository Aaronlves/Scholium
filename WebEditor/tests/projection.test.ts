import {describe, expect, it} from "vitest";
import {linkTargetAt} from "../projection";

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
});

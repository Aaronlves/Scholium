import {describe, expect, it} from "vitest";
import {linkTargetAt} from "../projection";

describe("exact link activation projection", () => {
  it("resolves wikilink, vector-link, and standard-link targets", () => {
    const source = "[[Note|Label]] +[[Support]] [Web](https://example.test)";
    expect(linkTargetAt(source, 4)).toBe("Note");
    expect(linkTargetAt(source, source.indexOf("Support"))).toBe("Support");
    expect(linkTargetAt(source, source.indexOf("Web"))).toBe("https://example.test");
  });
  it("does not activate ordinary prose", () => {
    expect(linkTargetAt("plain claim", 3)).toBeNull();
  });
});

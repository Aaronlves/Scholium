import {describe, expect, it} from "vitest";
import {footnotePreviewContent, footnoteReferenceAt, validatedLinkPreviews} from "../previews";

describe("preview projections", () => {
  it("accepts only bounded previews inside the current document", () => {
    expect(validatedLinkPreviews([
      {from: 0, to: 5, title: " Target ", relationship: "supports", fragment: "Heading", htmlBody: "<p>Body</p>"},
      {from: 6, to: 99, title: "Outside", htmlBody: "<p>No</p>"},
      {from: 6, to: 8, title: "", htmlBody: "<p>No</p>"},
      {from: 6, to: 8, title: "Bad relationship", relationship: "invented", htmlBody: "<p>Body</p>"},
    ], 12)).toEqual([
      {from: 0, to: 5, title: "Target", relationship: "supports", fragment: "Heading", htmlBody: "<p>Body</p>"},
      {from: 6, to: 8, title: "Bad relationship", relationship: undefined, fragment: undefined, htmlBody: "<p>Body</p>"},
    ]);
  });

  it("returns one referenced footnote definition with bounded continuations", () => {
    const source = "Text[^one] and [^two].\n\n[^one]: First line\n  continuation\n\n  - item\n    - nested\n[^two]: Other footnote";
    expect(footnotePreviewContent(source, "one"))
      .toBe("First line\ncontinuation\n\n- item\n  - nested");
    expect(footnotePreviewContent(source, "two")).toBe("Other footnote");
    expect(footnotePreviewContent(source, "missing")).toBeNull();
    expect(footnoteReferenceAt(source, source.indexOf("[^one]") + 3)).toBe("one");
    expect(footnoteReferenceAt(source, source.indexOf("[^one]:") + 3)).toBeNull();

    const literal = "`[^hidden]`\n\n[^hidden]: Not a preview";
    const codeRange = {from: 0, to: "`[^hidden]`".length};
    expect(footnoteReferenceAt(literal, 3, [codeRange])).toBeNull();
  });
});

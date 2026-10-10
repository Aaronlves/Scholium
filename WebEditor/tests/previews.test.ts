import {describe, expect, it} from "vitest";
import {validatedLinkPreviews} from "../previews";

describe("preview projections", () => {
  it("accepts only bounded previews inside the current document", () => {
    expect(validatedLinkPreviews([
      {from: 0, to: 5, title: " Target ", fragment: "Heading", htmlBody: "<p>Body</p>"},
      {from: 6, to: 99, title: "Outside", htmlBody: "<p>No</p>"},
      {from: 6, to: 8, title: "", htmlBody: "<p>No</p>"},
      {from: 6, to: 8, title: "Second", htmlBody: "<p>Body</p>"},
    ], 12)).toEqual([
      {from: 0, to: 5, title: "Target", isEmbedded: false, fragment: "Heading", htmlBody: "<p>Body</p>"},
      {from: 6, to: 8, title: "Second", isEmbedded: false, fragment: undefined, htmlBody: "<p>Body</p>"},
    ]);
  });

  it("keeps complete embedded-note HTML while ordinary previews remain bounded", () => {
    const longBody = `<p>${"complete ".repeat(4_000)}</p>`;
    const [embedded, ordinary] = validatedLinkPreviews([
      {from: 0, to: 5, title: "Embedded", isEmbedded: true, htmlBody: longBody},
      {from: 6, to: 11, title: "Ordinary", htmlBody: longBody},
    ], 12);
    expect(embedded.htmlBody).toBe(longBody);
    expect(ordinary.htmlBody.length).toBe(24_000);
  });

});

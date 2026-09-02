import {describe, expect, it} from "vitest";
import {linkAnnotationAfter} from "../link-annotation";

describe("link annotation source grammar", () => {
  it("owns multiline Markdown through the first unescaped closing delimiter", () => {
    const source = "[[Target]]{{First **reason**.\n\n- escaped \\}} text\n- second reason}} tail";
    const linkTo = "[[Target]]".length;
    expect(linkAnnotationAfter(source, linkTo)).toEqual({
      from: linkTo,
      to: source.indexOf(" tail"),
      contentFrom: linkTo + 2,
      contentTo: source.indexOf(" tail") - 2,
      markdown: "First **reason**.\n\n- escaped \\}} text\n- second reason",
    });
  });

  it("rejects empty, nested, unclosed, detached, and escaped openers", () => {
    for (const source of [
      "[[Target]]{{ }}",
      "[[Target]]{{` `}}",
      "[[Target]]{{---}}",
      "[[Target]]{{outer {{nested}} text}}",
      "[[Target]]{{unclosed",
      "[[Target]] {{detached}}",
      "[[Target]]\\{{escaped}}",
    ]) {
      expect(linkAnnotationAfter(source, "[[Target]]".length)).toBeNull();
    }
  });
});

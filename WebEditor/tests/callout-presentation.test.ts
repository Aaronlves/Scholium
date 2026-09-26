import {describe, expect, it} from "vitest";
import type {MarkdownEditingDialect} from "../protocol";
import {calloutDefinition} from "../callout-presentation";

const dialect: MarkdownEditingDialect = {
  version: 6,
  callouts: [
    {identifier: "orient", label: "Orientation", meaning: "Purpose and route."},
    {identifier: "cite", label: "Source", meaning: "Source anchor."},
    {identifier: "connect", label: "Connections", meaning: "Neighboring notes."},
    {identifier: "state", label: "Statement", meaning: "A compact claim."},
    {identifier: "illustrate", label: "Illustration", meaning: "An example."},
    {identifier: "quote", label: "Quotation", meaning: "Exact wording."},
    {identifier: "flag", label: "Caution", meaning: "A limitation."},
  ],
  linkAnnotation: {
    openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false,
  },
  footnotes: {
    namedReferenceOpening: "[^", namedReferenceClosing: "]", definitionSeparator: ":",
    inlineOpening: "^[", continuationIndentSpaces: 2, allowsTabContinuation: true,
    caseSensitiveIdentifiers: true, ordinalByFirstReference: true,
  },
  mathematics: {inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true},
};

describe("Callout presentation vocabulary", () => {
  it("assigns semantics only to built-in names and keeps unknown names neutral", () => {
    expect(calloutDefinition(dialect, "state").identifier).toBe("state");
    for (const unknown of ["mini", "bibliography", "project", "theorem", "objection", "case", "author", "torn", "bespoke"]) {
      expect(calloutDefinition(dialect, unknown).identifier).toBe("neutral");
    }
  });
});

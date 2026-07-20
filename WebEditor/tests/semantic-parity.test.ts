import {readFileSync} from "node:fs";
import {describe, expect, it} from "vitest";
import {projectDialectSemantics} from "../projection";
import type {MarkdownEditingDialect} from "../protocol";

const dialect: MarkdownEditingDialect = {
  version: 2,
  callouts: [
    {identifier: "orient", aliases: ["mini"], label: "Orientation", meaning: "Scope"},
    {identifier: "cite", aliases: ["bibli", "bibliography", "cited"], label: "Source", meaning: "Source"},
    {identifier: "connect", aliases: ["project"], label: "Connections", meaning: "Connections"},
    {identifier: "state", aliases: ["definition", "principle", "theorem", "argument", "objection", "reply"], label: "Statement", meaning: "Statement"},
    {identifier: "illustrate", aliases: ["example", "case", "dialogue"], label: "Illustration", meaning: "Illustration"},
    {identifier: "quote", aliases: ["quotation", "author", "long-quote"], label: "Quotation", meaning: "Quotation"},
    {identifier: "flag", aliases: ["warning", "caution", "source-warning", "torn", "question"], label: "Caution", meaning: "Caution"},
  ],
  vectorLinkOperators: [
    {marker: "", kind: "neutral", meaning: "Neutral"},
    {marker: "+", kind: "supports_target", meaning: "Supports"},
    {marker: "-", kind: "supported_by_target", meaning: "Supported by"},
    {marker: "?", kind: "incompatible", meaning: "Incompatible"},
  ],
  footnotes: {
    namedReferenceOpening: "[^",
    namedReferenceClosing: "]",
    definitionSeparator: ":",
    inlineOpening: "^[",
    continuationIndentSpaces: 2,
    allowsTabContinuation: true,
    caseSensitiveIdentifiers: true,
    ordinalByFirstReference: true,
  },
  mathematics: {
    inlineDelimiter: "$",
    displayDelimiter: "$$",
    singleDollarInline: true,
  },
};

interface Fixture {
  name: string;
  source: string;
  callouts: string[];
  links: Array<{target: string; vectorKind: string | null}>;
  footnoteDefinitions: string[];
  footnoteDefinitionContents: string[];
  footnoteReferences: string[];
  mathExpressions: Array<{kind: "inline" | "display"; content: string}>;
  sourceSlices: {
    calloutHeaders: string[];
    links: string[];
    footnoteDefinitions: string[];
    footnoteReferences: string[];
    mathExpressions: Array<{source: string; content: string}>;
  };
}

describe("Contracts semantic parity fixtures", () => {
  const fixtures = JSON.parse(readFileSync(
    new URL("../../Tests/ScholiumContractsTests/Fixtures/semantic-parity-fixtures.json", import.meta.url),
    "utf8",
  )) as Fixture[];
  for (const fixture of fixtures) {
    it(fixture.name, () => expect(projectDialectSemantics(fixture.source, dialect)).toEqual({
      callouts: fixture.callouts,
      links: fixture.links,
      footnoteDefinitions: fixture.footnoteDefinitions,
      footnoteDefinitionContents: fixture.footnoteDefinitionContents,
      footnoteReferences: fixture.footnoteReferences,
      mathExpressions: fixture.mathExpressions,
      sourceSlices: fixture.sourceSlices,
    }));
  }
});

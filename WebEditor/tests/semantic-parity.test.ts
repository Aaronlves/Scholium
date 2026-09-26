import {readFileSync} from "node:fs";
import {describe, expect, it} from "vitest";
import {projectDialectSemantics} from "./parity-projection";
import type {MarkdownEditingDialect} from "../protocol";

const dialect: MarkdownEditingDialect = {
  version: 6,
  callouts: [
    {identifier: "orient", label: "Orientation", meaning: "Scope"},
    {identifier: "cite", label: "Source", meaning: "Source"},
    {identifier: "connect", label: "Connections", meaning: "Connections"},
    {identifier: "state", label: "Statement", meaning: "Statement"},
    {identifier: "illustrate", label: "Illustration", meaning: "Illustration"},
    {identifier: "quote", label: "Quotation", meaning: "Quotation"},
    {identifier: "flag", label: "Caution", meaning: "Caution"},
  ],
  linkAnnotation: {
    openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false,
  },
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
  links: Array<{target: string; annotation: string | null}>;
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

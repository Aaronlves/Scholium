import {readFileSync} from "node:fs";
import {describe, expect, it} from "vitest";
import {projectDialectSemantics} from "../projection";
import type {MarkdownEditingDialect} from "../protocol";

const dialect: MarkdownEditingDialect = {
  version: 1,
  callouts: [
    {identifier: "orient", aliases: ["mini"], label: "Orientation", meaning: "Scope"},
    {identifier: "cite", aliases: ["bibli"], label: "Source", meaning: "Source"},
  ],
  vectorLinkOperators: [
    {marker: "", kind: "neutral", meaning: "Neutral"},
    {marker: "+", kind: "supports_target", meaning: "Supports"},
    {marker: "-", kind: "supported_by_target", meaning: "Supported by"},
    {marker: "?", kind: "incompatible", meaning: "Incompatible"},
  ],
};

interface Fixture {
  name: string;
  source: string;
  callouts: string[];
  links: Array<{target: string; vectorKind: string | null}>;
  footnoteDefinitions: string[];
  footnoteReferences: string[];
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
      footnoteReferences: fixture.footnoteReferences,
    }));
  }
});

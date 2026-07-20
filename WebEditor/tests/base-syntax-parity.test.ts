import {readFileSync} from "node:fs";
import {describe, expect, it} from "vitest";
import {projectBaseSyntax, type BaseSyntaxProjection} from "../projection";

interface Fixture extends BaseSyntaxProjection {
  name: string;
  source: string;
}

describe("Contracts base-syntax parity fixtures", () => {
  const fixtures = JSON.parse(readFileSync(
    new URL("../../Tests/ScholiumContractsTests/Fixtures/base-syntax-parity-fixtures.json", import.meta.url),
    "utf8",
  )) as Fixture[];

  for (const fixture of fixtures) {
    it(fixture.name, () => expect(projectBaseSyntax(fixture.source)).toEqual({
      blocks: fixture.blocks,
      inlines: fixture.inlines,
    }));
  }
});

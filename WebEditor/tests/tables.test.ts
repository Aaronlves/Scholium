import {describe, expect, it} from "vitest";
import {applySourceChanges} from "../transformations";
import {tableAt, tableTabAction, transformTableCommand} from "../tables";

const source = "| Claim | Status |\n|---|:---:|\n| Exact | Open |";

describe("guarded GFM table operations", () => {
  it("recognizes only consistent unambiguous tables", () => {
    expect(tableAt(source, source.indexOf("Exact"))?.position).toEqual({row: 1, column: 0, rowCount: 2, columnCount: 2});
    expect(tableAt("| A | B |\n|---|---|\n| one |", 25)).toBeNull();
    expect(tableAt("A | B\n--- | ---\none | two | extra", 22)).toBeNull();
  });
  it("edits only the chosen alignment separator", () => {
    const result = transformTableCommand(source, [{anchor: source.indexOf("Open"), head: source.indexOf("Open")}], "tableAlignRight");
    expect(result).not.toBeNull();
    expect(applySourceChanges(source, result!.changes)).toBe("| Claim | Status |\n|---|---:|\n| Exact | Open |");
  });
  it("adds a row without reformatting existing rows", () => {
    const offset = source.indexOf("Exact");
    const result = transformTableCommand(source, [{anchor: offset, head: offset}], "tableInsertRowAfter");
    expect(result).not.toBeNull();
    expect(applySourceChanges(source, result!.changes)).toBe(`${source}\n|  |  |`);
  });
  it("moves between cells and appends from the final cell", () => {
    const move = tableTabAction(source, source.indexOf("Exact"), false);
    expect(move?.changes).toEqual([]);
    expect(source.slice(move!.selections[0].anchor, move!.selections[0].head)).toBe("Open");
    const append = tableTabAction(source, source.indexOf("Open"), false);
    expect(applySourceChanges(source, append!.changes)).toBe(`${source}\n|  |  |`);
  });
});

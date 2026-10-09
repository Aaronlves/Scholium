import {describe, expect, it} from "vitest";
import {applySourceChanges} from "../transformations";
import {tableAt, tableCommandAvailable, tableTabAction, transformTableCommand} from "../tables";
import {Text} from "@codemirror/state";
import {scholiumMarkdownContentLanguage} from "../language";

const source = "| Claim | Status |\n|---|:---:|\n| Exact | Open |";

describe("guarded GFM table operations", () => {
  it("shares structural command availability with execution", () => {
    const header = tableAt(source, source.indexOf("Claim"))!.position;
    const body = tableAt(source, source.indexOf("Open"))!.position;
    expect(tableCommandAvailable("tableInsertRowBefore", header)).toBe(false);
    expect(tableCommandAvailable("tableInsertRowAfter", header)).toBe(true);
    expect(tableCommandAvailable("tableDeleteRow", header)).toBe(false);
    expect(tableCommandAvailable("tableDeleteRow", body)).toBe(false);
    expect(tableCommandAvailable("tableDeleteColumn", body)).toBe(true);
    expect(tableCommandAvailable("tableAlignRight", undefined)).toBe(false);
    expect(tableCommandAvailable("bold", body)).toBe(false);
  });
  it("retains a valid one-column GFM table and permits reducing two columns to one", () => {
    const single = "| Header |\n|---|\n| Body |";
    const parsed = scholiumMarkdownContentLanguage.language.parser.parse(single).topNode.getChild("Table");
    expect(parsed?.to).toBe(single.length);
    const position = tableAt(single, single.indexOf("Body"))!.position;
    expect(position.columnCount).toBe(1);
    expect(tableCommandAvailable("tableDeleteColumn", position)).toBe(false);
    expect(tableAt("Header\n---\nBody", 1)).toBeNull();
    const offset = source.indexOf("Open");
    const removed = transformTableCommand(source, [{anchor: offset, head: offset}], "tableDeleteColumn")!;
    const result = applySourceChanges(source, removed.changes);
    expect(result).toBe("| Claim |\n|---|\n| Exact |");
    expect(tableAt(result, result.indexOf("Exact"))?.position.columnCount).toBe(1);
    expect(scholiumMarkdownContentLanguage.language.parser.parse(result).topNode.getChild("Table")?.to)
      .toBe(result.length);
  });
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
  it("keeps the header adjacent to its delimiter when inserting from a header cell", () => {
    const offset = source.indexOf("Claim");
    const selection = [{anchor: offset, head: offset}];
    expect(transformTableCommand(source, selection, "tableInsertRowBefore")).toBeNull();
    const after = transformTableCommand(source, selection, "tableInsertRowAfter")!;
    const changed = applySourceChanges(source, after.changes);
    expect(changed).toBe("| Claim | Status |\n|---|:---:|\n|  |  |\n| Exact | Open |");
    expect(tableAt(changed, changed.indexOf("Exact"))?.position.rowCount).toBe(3);
  });
  it.each(["tableAlignLeft", "tableAlignCenter", "tableAlignRight"] as const)("maps a reversed body selection through %s separator changes", command => {
    const from = source.indexOf("Open"), to = from + "Open".length;
    const result = transformTableCommand(source, [{anchor: to, head: from}], command)!;
    const changed = applySourceChanges(source, result.changes);
    const range = result.selections[0];
    expect(range.anchor).toBeGreaterThan(range.head);
    expect(changed.slice(range.head, range.anchor)).toBe("Open");
  });
  it.each(["tableInsertColumnBefore", "tableInsertColumnAfter"] as const)("preserves the selected cell through all preceding %s edits", command => {
    const from = source.indexOf("Open"), to = from + "Open".length;
    const result = transformTableCommand(source, [{anchor: to, head: from}], command)!;
    const changed = applySourceChanges(source, result.changes);
    const range = result.selections[0];
    expect(changed.slice(range.head, range.anchor)).toBe("Open");
    expect(tableAt(changed, range.head)?.position.columnCount).toBe(3);
  });
  it("moves between cells and appends from the final cell", () => {
    const move = tableTabAction(source, source.indexOf("Exact"), false);
    expect(move?.changes).toEqual([]);
    expect(source.slice(move!.selections[0].anchor, move!.selections[0].head)).toBe("Open");
    const append = tableTabAction(source, source.indexOf("Open"), false);
    expect(applySourceChanges(source, append!.changes)).toBe(`${source}\n|  |  |`);
  });
  it("uses CodeMirror Text for the production table Tab path", () => {
    const document = Text.of(source.split("\n"));
    const move = tableTabAction(document, source.indexOf("Exact"), false);
    expect(move?.changes).toEqual([]);
    expect(source.slice(move!.selections[0].anchor, move!.selections[0].head)).toBe("Open");
  });
});

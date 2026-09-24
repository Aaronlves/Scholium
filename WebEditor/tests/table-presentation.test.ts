import {describe, expect, it} from "vitest";
import {tablePresentation} from "../table-presentation";

describe("semantic table presentation", () => {
  it("preserves header identity, column alignment, body rows, and edit offsets", () => {
    const source = "| Claim | Status | Count |\n|:---|:---:|---:|\n| A \\| B | Open | 2 |";
    const table = tablePresentation(source, 0, source.length);

    expect(table).not.toBeNull();
    expect(table?.header.map((cell) => cell.source)).toEqual(["Claim", "Status", "Count"]);
    expect(table?.header.map((cell) => cell.alignment)).toEqual(["left", "center", "right"]);
    expect(table?.body.map((row) => row.map((cell) => cell.source))).toEqual([
      ["A | B", "Open", "2"],
    ]);
    expect(table?.body[0][0].sourceOffset).toBe(source.indexOf("A \\| B"));
  });

  it("refuses a range that does not match one complete parsed table", () => {
    const source = "Before\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\nAfter";
    const from = source.indexOf("| A");
    const to = source.indexOf("\n\nAfter");
    expect(tablePresentation(source, from, to)).not.toBeNull();
    expect(tablePresentation(source, from + 1, to)).toBeNull();
    expect(tablePresentation(source, from, to - 1)).toBeNull();
  });
});

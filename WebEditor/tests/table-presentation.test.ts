import {describe, expect, it} from "vitest";
import {Text} from "@codemirror/state";
import {tablePresentation} from "../table-presentation";

describe("semantic table presentation", () => {
  it("preserves header identity, column alignment, body rows, and edit offsets", () => {
    const source = "| Claim | Status | Count |\n|:---|:---:|---:|\n| A \\| B | Open | 2 |";
    const table = tablePresentation(source, 0, source.length);

    expect(table).not.toBeNull();
    expect(table?.header.map((cell) => cell.source)).toEqual(["Claim", "Status", "Count"]);
    expect(table?.header.map((cell) => cell.alignment)).toEqual(["left", "center", "right"]);
    expect(table?.body.map((row) => row.map((cell) => cell.source))).toEqual([
      ["A \\| B", "Open", "2"],
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

  it.each(["\n", "\r\n"])("keeps string and rope table boundaries and Unicode offsets identical (%j)", newline => {
    const tableSource = "| 中文 🦉 | e\u0301 |\n|:---|---:|\n| A \\| B | **value** |".replaceAll("\n", newline);
    const source = `\ufeffBefore${newline}${newline}${tableSource}`;
    // Text keeps exactly the supplied UTF-16 units; callers choose whether
    // these are the exact source or the editor's normalized coordinates.
    const rope = Text.of(source.split("\n"));
    const from = source.indexOf("| 中文");
    const to = from + tableSource.length;
    const expected = tablePresentation(source, from, to);
    expect(expected).not.toBeNull();
    expect(tablePresentation(rope, from, to)).toEqual(expected);
    expect(expected?.header[1].sourceOffset).toBe(source.indexOf("e\u0301"));
    expect(expected?.body[0][0].sourceOffset).toBe(source.indexOf("A \\| B"));
    for (const [invalidFrom, invalidTo] of [[from + 1, to], [from, to - 1], [-1, to], [from, source.length + 1]]) {
      expect(tablePresentation(rope, invalidFrom, invalidTo)).toBeNull();
    }
  });
});

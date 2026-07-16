import {describe, expect, it} from "vitest";
import {continueList, indentList} from "../interaction";
import {applySourceChanges} from "../transformations";

describe("guarded list interaction", () => {
  it("continues bullet, task, and ordered lists", () => {
    for (const [source, expected] of [
      ["- claim", "- claim\n- "],
      ["- [x] checked", "- [x] checked\n- [ ] "],
      ["9. claim", "9. claim\n10. "],
    ]) {
      const result = continueList(source, [{anchor: source.length, head: source.length}]);
      expect(applySourceChanges(source, result!.changes)).toBe(expected);
    }
  });
  it("exits an empty list item by removing only its prefix", () => {
    const source = "Before\n  - ";
    const result = continueList(source, [{anchor: source.length, head: source.length}]);
    expect(applySourceChanges(source, result!.changes)).toBe("Before\n");
  });
  it("indents only proven list lines", () => {
    const source = "- one\n- two";
    const result = indentList(source, [{anchor: 0, head: source.length}], false);
    expect(applySourceChanges(source, result!.changes)).toBe("  - one\n  - two");
    expect(indentList("plain", [{anchor: 0, head: 0}], false)).toBeNull();
  });
});

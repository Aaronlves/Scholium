import {describe, expect, it} from "vitest";
import {continueCallout, continueList, indentList} from "../interaction";
import {applySourceChanges} from "../transformations";
import {Text} from "@codemirror/state";

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
  it("reads only CodeMirror Text lines on the production Enter and Tab path", () => {
    const source = "intro\n- one\n- two";
    const document = Text.of(source.split("\n"));
    const continued = continueList(document, [{anchor: source.length, head: source.length}]);
    expect(applySourceChanges(source, continued!.changes)).toBe("intro\n- one\n- two\n- ");
    const indented = indentList(document, [{anchor: 6, head: source.length}], false);
    expect(applySourceChanges(source, indented!.changes)).toBe("intro\n  - one\n  - two");
  });
});

describe("guarded Callout interaction", () => {
  it("continues a semantic Callout with its exact quote prefix", () => {
    const source = "> [!orient] Reading route";
    const result = continueCallout(source, [{anchor: source.length, head: source.length}]);

    expect(applySourceChanges(source, result!.changes))
      .toBe("> [!orient] Reading route\n> ");
    expect(result!.selections).toEqual([{anchor: source.length + 3, head: source.length + 3}]);
    expect(result!.undoLabel).toBe("Continue Callout");
  });

  it("exits on Return from an empty quoted Callout line", () => {
    const source = "> [!orient] Reading route\n> ";
    const result = continueCallout(source, [{anchor: source.length, head: source.length}]);

    expect(applySourceChanges(source, result!.changes))
      .toBe("> [!orient] Reading route\n");
    expect(result!.selections).toEqual([{anchor: source.length - 2, head: source.length - 2}]);
    expect(result!.undoLabel).toBe("Exit Callout");
  });

  it("does not continue ordinary quotations or nonempty selections", () => {
    const quotation = "> Ordinary quotation.";
    expect(continueCallout(quotation, [{anchor: quotation.length, head: quotation.length}]))
      .toBeNull();
    const callout = "> [!state] Claim";
    expect(continueCallout(callout, [{anchor: 2, head: callout.length}])).toBeNull();
  });
});

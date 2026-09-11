import {describe, expect, it} from "vitest";
import {continueCallout, continueList, indentList} from "../interaction";
import {applySourceChanges} from "../transformations";
import {Text} from "@codemirror/state";

describe("guarded list interaction", () => {
  it("continues bullet, task, and ordered lists", () => {
    for (const [source, expected] of [
      ["- claim", "- claim\n- "],
      ["- [x] checked", "- [x] checked\n- [ ] "],
      ["* [x] alternate", "* [x] alternate\n* [ ] "],
      ["12) [x] ordered task", "12) [x] ordered task\n13) [ ] "],
      ["9. claim", "9. claim\n10. "],
    ]) {
      const result = continueList(source, [{anchor: source.length, head: source.length}]);
      expect(applySourceChanges(source, result!.changes)).toBe(expected);
    }
  });
  it("exits empty list items by removing their complete marker track", () => {
    for (const source of ["Before\n  - ", "Before\n  -", "Before\n  4)   "]) {
      const result = continueList(source, [{anchor: source.length, head: source.length}]);
      expect(applySourceChanges(source, result!.changes)).toBe("Before\n");
    }
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
  it("keeps blockquote and Callout list indentation inside the quote track", () => {
    const source = "> [!state] Claims\n> - one\n>   - nested";
    const first = source.indexOf("> - one");
    const result = indentList(
      source,
      [{anchor: first, head: source.length}],
      false,
    );
    expect(applySourceChanges(source, result!.changes)).toBe(
      "> [!state] Claims\n>   - one\n>     - nested",
    );
  });
  it("removes one mixed indentation unit and maps a line-start caret after it", () => {
    const source = "\t- tabbed\n    - spaced";
    const result = indentList(
      source,
      [{anchor: 0, head: source.length}],
      true,
    );
    expect(applySourceChanges(source, result!.changes)).toBe("- tabbed\n  - spaced");
    expect(result!.selections).toEqual([{
      anchor: 0,
      head: source.length - 3,
    }]);
  });
  it("does not continue or indent a protected technical line", () => {
    const source = "```\n- code\n```";
    const lineIsProtected = (line: {number: number}) => line.number === 2;
    expect(continueList(source, [{anchor: 7, head: 7}], {lineIsProtected})).toBeNull();
    expect(indentList(source, [{anchor: 7, head: 7}], false, {lineIsProtected})).toBeNull();
  });
  it("keeps the mapped selection on both indented list lines for outdent", () => {
    const source = "  - first\n  - second\n\n```swift\n- code\n```\n";
    const result = indentList(source, [{anchor: 2, head: 20}], true);
    expect(result?.undoLabel).toBe("Outdent List");
    expect(applySourceChanges(source, result!.changes))
      .toBe("- first\n- second\n\n```swift\n- code\n```\n");
  });
  it("outdents only the nested lines in a mixed-depth selection", () => {
    const source = "- root\n  - nested";
    const result = indentList(source, [{anchor: 0, head: source.length}], true);
    expect(applySourceChanges(source, result!.changes)).toBe("- root\n- nested");
    expect(result!.undoLabel).toBe("Outdent List");
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

  it("continues the current list level inside a Callout", () => {
    for (const [source, expected] of [
      ["> [!state] Claims\n> - first", "> [!state] Claims\n> - first\n> - "],
      ["> [!state] Claims\n>   - nested", "> [!state] Claims\n>   - nested\n>   - "],
      ["> [!state] Claims\n> 9. ordered", "> [!state] Claims\n> 9. ordered\n> 10. "],
      ["> [!state] Claims\n> - [x] checked", "> [!state] Claims\n> - [x] checked\n> - [ ] "],
    ]) {
      const result = continueCallout(source, [{anchor: source.length, head: source.length}]);
      expect(applySourceChanges(source, result!.changes)).toBe(expected);
      expect(result!.undoLabel).toBe("Continue List");
    }
  });

  it("preserves the Callout quote on the production CodeMirror Text path", () => {
    const source = "> [!state] Claims\n> - first";
    const result = continueCallout(
      Text.of(source.split("\n")),
      [{anchor: source.length, head: source.length}],
    );
    expect(applySourceChanges(source, result!.changes))
      .toBe("> [!state] Claims\n> - first\n> - ");
  });

  it("exits an empty nested list before exiting its Callout", () => {
    const source = "> [!state] Claims\n> - ";
    const listExit = continueCallout(source, [{anchor: source.length, head: source.length}]);
    const quotedBlank = applySourceChanges(source, listExit!.changes);
    expect(quotedBlank).toBe("> [!state] Claims\n> ");
    expect(listExit!.undoLabel).toBe("Exit List");

    const calloutExit = continueCallout(quotedBlank, [{anchor: quotedBlank.length, head: quotedBlank.length}]);
    expect(applySourceChanges(quotedBlank, calloutExit!.changes))
      .toBe("> [!state] Claims\n");
    expect(calloutExit!.undoLabel).toBe("Exit Callout");
  });

  it("does not continue ordinary quotations or nonempty selections", () => {
    const quotation = "> Ordinary quotation.";
    expect(continueCallout(quotation, [{anchor: quotation.length, head: quotation.length}]))
      .toBeNull();
    const callout = "> [!state] Claim";
    expect(continueCallout(callout, [{anchor: 2, head: callout.length}])).toBeNull();
  });
});

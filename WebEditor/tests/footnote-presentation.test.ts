import {describe, expect, it} from "vitest";
import {footnotePresentation, scholiumFootnoteDialect} from "../footnote-presentation";

describe("footnotePresentation", () => {
  it("fails closed for a dialect the renderer does not implement", () => {
    expect(footnotePresentation("Claim[^x].\n\n[^x]: Basis", [], {
      ...scholiumFootnoteDialect,
      continuationIndentSpaces: 4,
    })).toEqual({definitions: [], references: []});
  });

  it("orders definitions by first reference and preserves repeated occurrences", () => {
    const source = "Second[^b], first[^a], again[^b].\n\n[^a]: Alpha\n[^b]: **Beta**";
    const projection = footnotePresentation(source);

    expect(projection.references.map(({identifier, ordinal, occurrence}) => ({identifier, ordinal, occurrence})))
      .toEqual([
        {identifier: "b", ordinal: 1, occurrence: 1},
        {identifier: "a", ordinal: 2, occurrence: 1},
        {identifier: "b", ordinal: 1, occurrence: 2},
      ]);
    expect(projection.definitions.map(({identifier, ordinal, content}) => ({identifier, ordinal, content})))
      .toEqual([
        {identifier: "b", ordinal: 1, content: "**Beta**"},
        {identifier: "a", ordinal: 2, content: "Alpha"},
      ]);
    expect(projection.definitions.map((definition) => source.slice(
      definition.contentFrom,
      definition.contentFrom + definition.content.length,
    ))).toEqual(["**Beta**", "Alpha"]);
  });

  it("captures bounded multiline definitions and leaves the following block outside", () => {
    const source = "Text[^one].\n\n[^one]: First\n  second\n\tthird\n\n  final\nFollowing";
    const projection = footnotePresentation(source);
    const definition = projection.definitions[0];

    expect(definition.content).toBe("First\nsecond\nthird\n\nfinal");
    expect(source.slice(definition.contentFrom, definition.contentFrom + 5)).toBe("First");
    expect(source.slice(definition.from, definition.to)).toBe("[^one]: First\n  second\n\tthird\n\n  final\n");
  });

  it("locates the first editable content after an empty definition line", () => {
    const source = "Text[^one].\n\n[^one]:\n  Editable continuation";
    const definition = footnotePresentation(source).definitions[0];

    expect(source.slice(definition.contentFrom)).toBe("Editable continuation");
  });

  it("preserves nested block indentation inside an owned definition", () => {
    const source = [
      "Claim[^blocks].",
      "",
      "[^blocks]: First paragraph.",
      "",
      "  - Outer item",
      "    - Nested item",
      "",
      "  ```swift",
      "  let value = 1",
      "  ```",
      "Following paragraph.",
    ].join("\n");
    const codeFrom = source.indexOf("  ```swift");
    const projection = footnotePresentation(source, [{from: codeFrom, to: source.indexOf("Following")}]);
    const definition = projection.definitions[0];

    expect(definition.content).toBe([
      "First paragraph.",
      "",
      "- Outer item",
      "  - Nested item",
      "",
      "```swift",
      "let value = 1",
      "```",
    ].join("\n"));
    expect(source.slice(definition.from, definition.to)).not.toContain("Following paragraph.");
  });

  it("projects inline, missing, unreferenced, escaped, and duplicate forms without repair", () => {
    const source = "Inline ^[note], missing[^none], escaped \\[^skip].\n\n[^unused]: Hidden\n[^unused]: Duplicate";
    const projection = footnotePresentation(source);

    expect(projection.references.map((reference) => reference.identifier))
      .toEqual(["inline-1", "none"]);
    expect(projection.references[0].definitionFrom).toBe(projection.references[0].from);
    expect(projection.references[1].definitionFrom).toBeNull();
    const unused = projection.definitions.find((definition) => definition.identifier === "unused");
    expect(unused?.ordinal).toBeNull();
    expect(unused?.content).toBe("Hidden");
    expect(projection.definitions.filter((definition) => definition.identifier === "unused")).toHaveLength(1);
  });

  it("excludes protected source ranges", () => {
    const source = "`[^code]` and [^real]\n\n[^code]: Code\n[^real]: Real";
    const codeFrom = source.indexOf("`[^code]`");
    const projection = footnotePresentation(source, [{from: codeFrom, to: codeFrom + 9}]);

    expect(projection.references.map((reference) => reference.identifier)).toEqual(["real"]);
    expect(projection.definitions.find((definition) => definition.identifier === "code")?.ordinal).toBeNull();
  });
});

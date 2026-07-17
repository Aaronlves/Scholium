import {describe, expect, it} from "vitest";
import {
  applyNormalizedChangesToExactSource,
  exactOffsetForNormalizedOffset,
  normalizedDocumentText,
} from "../state";

describe("exact source mirror", () => {
  it("maps normalized CodeMirror offsets across mixed line endings", () => {
    const source = "one\r\ntwo\nthree\r\n";
    expect(normalizedDocumentText(source)).toBe("one\ntwo\nthree\n");
    expect(exactOffsetForNormalizedOffset(source, 4)).toBe(5);
    expect(exactOffsetForNormalizedOffset(source, 8)).toBe(9);
    expect(exactOffsetForNormalizedOffset(source, 14)).toBe(source.length);
  });

  it("preserves untouched LF and CRLF bytes around an edit", () => {
    const source = "one\r\ntwo\nthree\r\n";
    const normalized = normalizedDocumentText(source);
    const insertionPoint = normalized.indexOf("two") + 3;
    const changed = applyNormalizedChangesToExactSource(source, [{
      from: insertionPoint,
      to: insertionPoint,
      insert: "!\nnext",
    }]);

    expect(changed).toBe("one\r\ntwo!\r\nnext\nthree\r\n");
    expect(normalizedDocumentText(changed!)).toBe("one\ntwo!\nnext\nthree\n");
  });

  it("returns the exact mixed-newline source when no changes occur", () => {
    const source = "\uFEFF---\r\ntitle: Exact\n---\r\nBody\n";
    expect(applyNormalizedChangesToExactSource(source, [])).toBe(source);
  });
});

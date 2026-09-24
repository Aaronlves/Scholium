import {describe, expect, it} from "vitest";
import {
  applyNormalizedChangesToExactSource,
  ExactSourceMirror,
  exactOffsetForNormalizedOffset,
  normalizedDocumentText,
} from "../state";

function referenceOffset(source: string, requested: number) {
  let exact = 0;
  let normalized = 0;
  while (exact < source.length && normalized < requested) {
    exact += source.charCodeAt(exact) === 13 && source.charCodeAt(exact + 1) === 10 ? 2 : 1;
    normalized += 1;
  }
  return normalized === requested ? exact : null;
}

function referenceApply(
  source: string,
  change: {from: number; to: number; insert: string},
) {
  const from = referenceOffset(source, change.from)!;
  const to = referenceOffset(source, change.to)!;
  const normalizedInsert = normalizedDocumentText(change.insert);
  const insert = source.includes("\r\n")
    ? normalizedInsert.replaceAll("\n", "\r\n")
    : normalizedInsert;
  return source.slice(0, from) + insert + source.slice(to);
}

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

  it("validates removed source and updates mixed line-ending offsets atomically", () => {
    const mirror = new ExactSourceMirror("one\r\ntwo\nthree\r\n");
    expect(mirror.apply([
      {from: 4, to: 7, insert: "second\nnext", removed: "two"},
      {from: 13, to: 13, insert: "!", removed: ""},
    ])).toBe(true);
    expect(mirror.text).toBe("one\r\nsecond\r\nnext\nthree!\r\n");

    const beforeRejectedChange = mirror.text;
    expect(mirror.apply([
      {from: 4, to: 10, insert: "invalid", removed: "not-second"},
    ])).toBe(false);
    expect(mirror.text).toBe(beforeRejectedChange);
  });

  it("matches a reference scan through deterministic mixed-newline edits", () => {
    let reference = "alpha\r\nbeta\ngamma\r\n研究\n";
    const mirror = new ExactSourceMirror(reference);
    let seed = 0x5c10_1a7e;
    const next = () => {
      seed = (Math.imul(seed, 1_664_525) + 1_013_904_223) >>> 0;
      return seed;
    };
    const inserts = ["x", "研究", "\nnext", "", "🧭"];
    for (let iteration = 0; iteration < 250; iteration += 1) {
      const normalized = normalizedDocumentText(reference);
      const from = next() % (normalized.length + 1);
      const deletion = Math.min(next() % 4, normalized.length - from);
      const to = from + deletion;
      const insert = inserts[next() % inserts.length];
      const removed = normalized.slice(from, to);
      expect(mirror.apply([{from, to, insert, removed}])).toBe(true);
      reference = referenceApply(reference, {from, to, insert});
      expect(mirror.text).toBe(reference);
    }
  });

  it("reports the 100k exact-source input regression scenario", () => {
    const exact = Array.from({length: 5_000}, (_, index) =>
      `Research line ${index.toString().padStart(4, "0")} 范围.\r\n`).join("");
    const mirror = new ExactSourceMirror(exact);
    let normalizedLength = normalizedDocumentText(exact).length;
    const startedAt = performance.now();
    for (let index = 0; index < 200; index += 1) {
      expect(mirror.apply([{
        from: normalizedLength,
        to: normalizedLength,
        insert: "x",
        removed: "",
      }])).toBe(true);
      normalizedLength += 1;
    }
    const elapsed = performance.now() - startedAt;
    console.log(`EXACT_SOURCE_INPUT_MICROBENCH ${elapsed.toFixed(3)}ms`);
    expect(mirror.text.endsWith("x".repeat(200))).toBe(true);
  });
});

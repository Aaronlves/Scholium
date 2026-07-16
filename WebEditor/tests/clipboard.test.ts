import {DOMParser} from "linkedom";
import {beforeAll, describe, expect, it} from "vitest";
import {convertClipboardHTML, pasteAsMarkdown, sanitizeClipboardHTML} from "../clipboard";

beforeAll(() => {
  Object.defineProperty(globalThis, "DOMParser", {value: DOMParser, configurable: true});
});

describe("inert clipboard conversion", () => {
  it("removes executable and resource-bearing content before parsing", () => {
    const safe = sanitizeClipboardHTML('<script>steal()</script><img src="https://tracker.test/a" alt="figure"><p onclick="run()" style="background:url(https://tracker.test)">Claim</p>');
    expect(safe).not.toMatch(/script|src=|onclick|style=|tracker/);
    expect(safe).toContain("figure");
  });
  it("converts only approved scholarly structures", () => {
    expect(convertClipboardHTML("<h2>Claim</h2><p><strong>Exact</strong> and <a href='https://example.test/a'>linked</a>.</p><ul><li>Reason</li></ul>")).toBe(
      "## Claim\n\n**Exact** and [linked](https://example.test/a).\n\n- Reason",
    );
  });
  it("converts simple tables and falls back to readable plain text", () => {
    expect(convertClipboardHTML("<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>")).toBe(
      "| A | B |\n| --- | --- |\n| 1 | 2 |",
    );
    expect(pasteAsMarkdown({plainText: "Readable", html: "<script>bad()</script>"})).toBe("Readable");
  });
});

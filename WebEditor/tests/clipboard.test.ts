import {DOMParser} from "linkedom";
import {beforeAll, describe, expect, it} from "vitest";
import {convertClipboardHTML, decodeClipboardPayload, pasteAsMarkdown, sanitizeClipboardHTML} from "../clipboard";

beforeAll(() => {
  Object.defineProperty(globalThis, "DOMParser", {value: DOMParser, configurable: true});
});

describe("inert clipboard conversion", () => {
  it("removes executable and resource-bearing content before parsing", () => {
    const safe = sanitizeClipboardHTML('<script>steal()</script><img src="https://tracker.test/a" alt="figure"><p onclick="run()" style="background:url(https://tracker.test)">Claim</p>');
    expect(safe).not.toMatch(/script|src=|onclick|style=|tracker/);
    expect(safe).toContain("figure");
  });
  it("decodes image alternative text exactly once using HTML attribute rules", () => {
    expect(convertClipboardHTML('<img src="https://tracker.test/a" alt="A &amp; B">')).toBe("A & B");
    expect(convertClipboardHTML('<img alt="A &amp;amp; B &#x1F9ED; &notit;">'))
      .toBe("A &amp; B 🧭 &notit;");
    expect(convertClipboardHTML('<img alt="&lt;script&gt;literal&lt;/script&gt;">'))
      .toBe("\\<script\\>literal\\</script\\>");
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
  it("accepts only the structured clipboard payload", () => {
    expect(decodeClipboardPayload('{"plainText":"Exact","html":"<strong>Exact</strong>"}')).toEqual({
      plainText: "Exact",
      html: "<strong>Exact</strong>",
    });
    expect(decodeClipboardPayload("legacy plain argument")).toBeUndefined();
    expect(decodeClipboardPayload(undefined)).toBeUndefined();
  });
  it("rejects oversized plain text without truncating a character and falls back from oversized HTML", () => {
    const oversized = "x".repeat(1_999_999) + "😀";
    expect(decodeClipboardPayload(JSON.stringify({plainText: oversized}))).toBeUndefined();
    expect(decodeClipboardPayload(JSON.stringify({plainText: "Complete text", html: oversized})))
      .toEqual({plainText: "Complete text", html: undefined});
    expect(pasteAsMarkdown({plainText: "Complete text", html: oversized})).toBe("Complete text");
  });
  it.each([
    ["a*b_[c]\\d", "`a*b_[c]\\d`"],
    ["a`b", "``a`b``"],
    ["`literal", "`` `literal ``"],
    ["literal`", "`` literal` ``"],
    [" a b ", "`  a b  `"],
    ["   ", "`   `"],
    ["first\nsecond", "`first second`"],
    ["", ""],
  ])("preserves literal inline-code content %j", (text, expected) => {
    expect(convertClipboardHTML(`<p><code>${text}</code></p>`)).toBe(expected);
  });
  it("retains code line breaks and highlighted text without adding Markdown escapes", () => {
    expect(convertClipboardHTML('<p><code><span class="syntax">first*</span><br><span>second_</span></code></p>'))
      .toBe("`first* second_`");
  });
  it("preserves fenced code whitespace and explicit HTML line breaks", () => {
    expect(convertClipboardHTML('<div><pre><code>first  <br><br><br>  last\n</code></pre></div>'))
      .toBe("```\nfirst  \n\n\n  last\n```");
  });
  it("preserves fenced code whitespace inside quote and list containers", () => {
    expect(convertClipboardHTML('<blockquote><pre>first  \n\n\nlast</pre></blockquote>'))
      .toBe("> ```\n> first  \n> \n> \n> last\n> ```");
    expect(convertClipboardHTML('<ul><li><pre>first  \n\n\nlast</pre></li></ul>'))
      .toBe("- ```\n  first  \n  \n  \n  last\n  ```");
  });
  it("keeps ordered-list code inside its item's full marker indentation", () => {
    expect(convertClipboardHTML('<ol><li><pre>first  \n\nlast</pre></li></ol>'))
      .toBe("1. ```\n   first  \n   \n   last\n   ```");
  });
  it("keeps multi-digit and nested ordered-list code correctly indented", () => {
    const preceding = "<li>Item</li>".repeat(9);
    expect(convertClipboardHTML(`<ol>${preceding}<li><pre>first\nlast</pre></li></ol>`))
      .toContain("10. ```\n    first\n    last\n    ```");
    expect(convertClipboardHTML('<ul><li>Outer<ol><li><pre>first\nlast</pre></li></ol></li></ul>'))
      .toBe("- Outer\n  1. ```\n     first\n     last\n     ```");
  });
  it("keeps spanning-cell text instead of dropping it to force a rectangular table", () => {
    const html = '<table><tr><td colspan="2">First claim</td><td>A</td><td>B</td></tr>'
      + '<tr><td rowspan="2">Second claim</td><td>C</td><td>D</td></tr></table>';
    expect(convertClipboardHTML(html)).toBe("First claim\tA\tB\nSecond claim\tC\tD");
  });
});

import {parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {appendMarkdownBlocks} from "../markdown-fragment";

describe("appendMarkdownBlocks", () => {
  it("preserves nested footnote block structure without executable HTML", () => {
    const {document} = parseHTML("<html><body><div id='root'></div></body></html>");
    const root = document.querySelector<HTMLElement>("#root")!;
    appendMarkdownBlocks([
      "First **reason**.",
      "",
      "- Outer item",
      "  - Nested *item*",
      "",
      "> Quoted reason.",
      "",
      "```swift",
      "let value = 1",
      "```",
      "",
      "<script>alert('no')</script>",
    ].join("\n"), root);

    expect(root.querySelector("p strong")?.textContent).toBe("reason");
    expect(root.querySelector("ul > li > ul > li em")?.textContent).toBe("item");
    expect(root.querySelector("blockquote p")?.textContent).toBe("Quoted reason.");
    expect(root.querySelector("pre code.language-swift")?.textContent).toBe("let value = 1");
    expect(root.querySelector("script")).toBeNull();
    expect(root.textContent).toContain("<script>alert('no')</script>");
  });

  it("reuses callout, table, and mathematics components inside a fragment", () => {
    const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
    window.scholiumMath = {
      version: 1,
      render: ({source, kind}) => ({
        ok: true as const,
        html: `<span class="katex" data-kind="${kind}">${source}</span>`,
      }),
    };
    const root = document.querySelector<HTMLElement>("#root")!;
    appendMarkdownBlocks([
      "> [!state] Main claim",
      "> Body with $x^2$.",
      "",
      "| Formula | Status |",
      "|:---|---:|",
      "| $y$ | Open |",
      "",
      "$$",
      "x + y",
      "$$",
    ].join("\n"), root, {
      mathematics: {
        inlineDelimiter: "$",
        displayDelimiter: "$$",
        singleDollarInline: true,
      },
      resolveCallout: (rawKind) => ({
        identifier: rawKind === "state" ? "state" : "neutral",
        label: rawKind === "state" ? "Statement" : "Note",
        meaning: "Semantic role",
      }),
    });

    expect(root.querySelector(".scholium-callout-state .scholium-callout-title")?.textContent)
      .toBe("Main claim");
    expect(root.querySelector(".scholium-callout-content .scholium-math-rendered .katex")?.textContent)
      .toBe("x^2");
    expect(root.querySelectorAll("table.scholium-table th")).toHaveLength(2);
    expect(root.querySelector("table .scholium-math-rendered .katex")?.textContent).toBe("y");
    expect(root.querySelector(".scholium-math-display .katex")?.textContent).toBe("x + y");
  });
});

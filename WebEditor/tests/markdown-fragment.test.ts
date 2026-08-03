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
    expect(root.querySelector("p")?.getAttribute("dir")).toBe("auto");
    expect(root.querySelector("li")?.getAttribute("dir")).toBe("auto");
    expect(root.querySelector("blockquote")?.getAttribute("dir")).toBe("auto");
    expect(root.querySelector("pre")?.getAttribute("dir")).toBe("ltr");
    expect(root.querySelector("pre code")?.getAttribute("dir")).toBe("ltr");
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
    const source = [
      "> [!state] Main claim",
      "> Body with $x^2$ and [[work-031|a linked note]].",
      "",
      "| Formula | Status |",
      "|:---|---:|",
      "| $y$ | Open |",
      "",
      "$$",
      "x + y",
      "$$",
    ].join("\n");
    appendMarkdownBlocks(source, root, {
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
      resolveVectorLink: () => "neutral",
      sourceOffset: (offset) => 100 + offset,
    });

    expect(root.querySelector(".scholium-callout-state .scholium-callout-title")?.textContent)
      .toBe("Main claim");
    expect(root.querySelector(".scholium-callout-state .scholium-callout-title")?.getAttribute("dir"))
      .toBe("auto");
    expect(root.querySelector(".scholium-callout-content .scholium-math-rendered .katex")?.textContent)
      .toBe("x^2");
    const calloutLink = root.querySelector<HTMLElement>(
      ".scholium-callout-content [data-scholium-link-target]",
    );
    expect(calloutLink?.textContent).toBe("a linked note");
    expect(calloutLink?.textContent).not.toContain("[[");
    expect(calloutLink?.dataset.scholiumLinkTarget).toBe("work-031");
    expect(Number(calloutLink?.dataset.scholiumSourceFrom))
      .toBe(100 + source.indexOf("[[work-031|a linked note]]"));
    expect(root.querySelectorAll("table.scholium-table th")).toHaveLength(2);
    expect([...root.querySelectorAll("table.scholium-table th, table.scholium-table td")]
      .every((cell) => cell.getAttribute("dir") === "auto")).toBe(true);
    expect(root.querySelector("table .scholium-math-rendered .katex")?.textContent).toBe("y");
    expect(root.querySelector(".scholium-math-display .katex")?.textContent).toBe("x + y");
  });

  it("keeps title-only Callouts visible and treats an Orient title as body prose", () => {
    const {document} = parseHTML("<html><body><div id='root'></div></body></html>");
    const root = document.querySelector<HTMLElement>("#root")!;
    const resolveCallout = (rawKind: string) => ({
      identifier: rawKind,
      label: rawKind === "orient" ? "Orient" : "Statement",
      meaning: "Semantic role",
    });

    appendMarkdownBlocks("> [!state] Title only", root, {resolveCallout});
    appendMarkdownBlocks("> [!orient] Reading **route**", root, {resolveCallout});

    expect(root.querySelector(".scholium-callout-state .scholium-callout-title")?.textContent)
      .toBe("Title only");
    expect(root.querySelector(".scholium-callout-orient .scholium-callout-title"))
      .toBeNull();
    expect(root.querySelector(".scholium-callout-orient-title-body")?.textContent)
      .toBe("Reading route");
    expect(root.querySelector(".scholium-callout-orient-title-body strong")?.textContent)
      .toBe("route");
  });
});

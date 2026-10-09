import {parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {appendMarkdownBlocks, renderedTextSourceOffset} from "../markdown-fragment";
import {populatePreviewDocument, renderPreviewMathNodes} from "../preview-popover";

function fragment(source: string) {
  const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
  window.scholiumMath = undefined;
  const root = document.querySelector<HTMLElement>("#root")!;
  appendMarkdownBlocks(source, root, {sourceOffset: offset => 100 + offset});
  return {document, window, root};
}

describe("source-faithful Markdown fragment coverage", () => {
  it.each(["====", "----"])("retains Setext heading content and exact nested source locations: %s", underline => {
    const source = `Before.\n\nImportant *claim*\n${underline}\n\nFollowing.`;
    const {root} = fragment(source);
    const heading = root.querySelector(underline[0] === "=" ? "h1" : "h2")!;
    expect(heading.textContent).toBe("Important claim");
    const text = heading.querySelector("em")!.firstChild!;
    expect(renderedTextSourceOffset(text, 2)).toBe(100 + source.indexOf("claim") + 2);
    expect(root.textContent).toContain("Following.");
  });

  it("retains indented code lines, blank lines and literal markup", () => {
    const source = "Before.\n\n    let x = 1\n\n    <tag>\n\nFollowing.";
    const {root} = fragment(source);
    const code = root.querySelector("pre code")!;
    expect(code.textContent).toBe("let x = 1\n\n<tag>");
    expect(code.querySelector("tag")).toBeNull();
    expect(renderedTextSourceOffset(code.firstChild!, 4)).toBe(100 + source.indexOf("let x") + 4);
  });

  it("preserves task body formatting with native-compatible read-only checked semantics", () => {
    const {root} = fragment("- [ ] Task **content**\n- [x] Completed *task*");
    const checks = [...root.querySelectorAll<HTMLInputElement>(".scholium-task-checkbox")];
    expect(checks.map(checkbox => [checkbox.checked, checkbox.disabled, checkbox.getAttribute("aria-label")]))
      .toEqual([[false, true, "Incomplete task"], [true, true, "Completed task"]]);
    expect(root.querySelector("li strong")?.textContent).toBe("content");
    expect(root.querySelector("li em")?.textContent).toBe("task");
    expect(root.textContent).toBe("Task contentCompleted task");
  });

  it("retains passive task states across the native preview HTML serialization boundary", () => {
    const {root} = fragment("- [x] Completed\n- [ ] Incomplete");
    const serialized = root.innerHTML;
    populatePreviewDocument(root, {from: 0, to: 1, title: "Tasks", isEmbedded: false, htmlBody: serialized});
    const tasks = [...root.querySelectorAll<HTMLInputElement>(".scholium-task-checkbox")];
    expect(tasks).toHaveLength(2);
    expect(tasks.map(task => task.hasAttribute("checked"))).toEqual([true, false]);
    expect(tasks.every(task => task.hasAttribute("disabled"))).toBe(true);
    expect(root.textContent).toBe("CompletedIncomplete");
  });

  it("uses parsed link destinations while rendering nested labels and exact paragraph offsets", () => {
    const source = "First paragraph.\n\n[**Strong** and \\*literal\\* &amp; text](target.md \"A title\")";
    const {root} = fragment(source);
    const link = root.querySelector<HTMLElement>(".cm-live-link")!;
    expect(link.textContent).toBe("Strong and *literal* & text");
    expect(link.dataset.scholiumLinkTarget).toBe("target.md");
    expect(link.dataset.scholiumSourceFrom).toBe(String(100 + source.indexOf("[**")));
    expect(renderedTextSourceOffset(link.querySelector("strong")!.firstChild!, 3))
      .toBe(100 + source.indexOf("Strong") + 3);
  });

  it("keeps source locations absolute through quotes, task bodies and table display transforms", () => {
    const source = "Before.\n\n> Quoted **reason**.\n\n- [ ] Task *work*\n\n"
      + "| A | B |\n| --- | --- |\n| a\\|b **proof** | other |";
    const {root} = fragment(source);
    for (const [selector, text] of [["blockquote strong", "reason"], ["li em", "work"], ["td strong", "proof"]]) {
      const node = root.querySelector(selector)!.firstChild!;
      expect(renderedTextSourceOffset(node, 1)).toBe(100 + source.indexOf(text) + 1);
    }
  });

  it("keeps unresolved reference links as exact source without inventing a target", () => {
    const {root} = fragment("[Label][target]\n\n[target]: target.md");
    expect(root.textContent).toBe("[Label][target]");
    expect(root.querySelector("[data-scholium-link-target]")).toBeNull();
  });

  it("renders parser-owned highlighting without exposing its delimiters", () => {
    const {root} = fragment("Before ==highlight== after.");
    expect(root.querySelector("mark")?.textContent).toBe("highlight");
    expect(root.textContent).toBe("Before highlight after.");
  });

  it("retains display math without an optional dialect and hydrates it after runtime arrival", async () => {
    const source = "$$\nx+1\n$$";
    const {root, window} = fragment(source);
    expect(root.querySelector(".scholium-math-source")?.textContent).toBe(source);
    expect(root.querySelector(".scholium-math-error")).toBeNull();
    await Promise.resolve();
    window.scholiumMath = {version: 1, render: request => ({ok: true, html: `<math><mi>${request.source}</mi></math>`})};
    renderPreviewMathNodes(root);
    renderPreviewMathNodes(root);
    expect(root.querySelectorAll(".scholium-math-output")).toHaveLength(1);
    expect(root.querySelector("math")?.textContent).toBe("x+1");
    expect(root.querySelector(".scholium-math-source")?.textContent).toBe(source);
  });

  it("preserves an authored escaped pipe when pending table math fails after runtime arrival", async () => {
    const source = "| Expression | Other |\n| --- | --- |\n| $\\bad{x\\|y}$ | text |";
    const {root, window} = fragment(source);
    const exact = "$\\bad{x\\|y}$";
    expect(root.querySelector(".scholium-math-source")?.textContent).toBe(exact);
    const received: string[] = [];
    await Promise.resolve();
    window.scholiumMath = {version: 1, render: request => {
      received.push(request.source);
      return {ok: false, reason: "unsupported-mathematics"};
    }};
    renderPreviewMathNodes(root);
    expect(received).toEqual(["\\bad{x|y}"]);
    expect(root.querySelector(".scholium-math-error .scholium-math-source")?.textContent).toBe(exact);
  });

  it("renders a parser-admitted single-column table", () => {
    const source = "| One column |\n| --- |\n| Cell |";
    const {root} = fragment(source);
    expect(root.querySelector("th")?.textContent).toBe("One column");
    expect(root.querySelector("td")?.textContent).toBe("Cell");
  });

  it("keeps parser-admitted tables outside the editable table model as exact source", () => {
    const source = "| A | B |\n| --- | --- |\n| Short row |";
    const {root} = fragment(source);
    expect(root.querySelector("pre code")?.textContent).toBe(source);
  });

  it("preserves only explicitly disabled task checkboxes when sanitizing preview content", () => {
    const {root} = fragment("");
    populatePreviewDocument(root, {from: 0, to: 1, title: "Preview", isEmbedded: false, htmlBody: `
      <input class="scholium-task-checkbox" type="checkbox" checked disabled onclick="attack()">
      <input class="scholium-task-checkbox" type="checkbox" disabled>
      <input class="scholium-task-checkbox" type="checkbox">
      <input class="scholium-task-checkbox" type="text" disabled>
      <input type="checkbox" disabled>
      <input class="scholium-task-checkbox" disabled>
      <button>Not admitted</button><script>attack()</script>`});
    const checkboxes = [...root.querySelectorAll<HTMLInputElement>("input")];
    expect(checkboxes).toHaveLength(2);
    expect(checkboxes.map(checkbox => checkbox.hasAttribute("checked"))).toEqual([true, false]);
    expect(checkboxes.every(checkbox => checkbox.hasAttribute("disabled")
      && checkbox.tabIndex === -1 && !checkbox.hasAttribute("onclick"))).toBe(true);
    expect(root.querySelector("button,script")).toBeNull();
  });
});

import {parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {createInterfaceLocalizer} from "../localization";
import {localizeRenderedInterface} from "../rendered-interface-localization";

const localize = createInterfaceLocalizer({languageTag: "zh-Hans", strings: {
  Statement: "论点",
  "Isolates a claim, definition, principle, formula, distinction, or compact argument without endorsing it.": "呈现论点，而不表示认可。",
  Caution: "限定",
  "Marks a limitation, unresolved dependency, source restriction, or interpretive warning.": "说明限制或解释上的保留。",
  "{label}. {meaning}": "{label}。{meaning}",
  "Footnote {ordinal}": "脚注 {ordinal}",
  "Return to footnote reference {ordinal}": "返回脚注 {ordinal} 的引用处",
  Footnotes: "脚注",
  "Completed task": "已完成的任务",
  "Incomplete task": "未完成的任务",
  "Markdown table": "Markdown 表格",
  "Show Link Annotation for {title}": "显示“{title}”的链接注释",
  "Hide Link Annotation for {title}": "隐藏“{title}”的链接注释",
}});

describe("renderer-owned interface localization", () => {
  it("localizes generated roles and default titles without changing authored or nested content", () => {
    const {document} = parseHTML(`<html><body><div id="root">
      <aside class="scholium-callout scholium-callout-state">
        <header><span class="scholium-callout-role">Statement</span><span class="scholium-callout-title">Authored 标题</span></header>
        <p>Exact é quoted source.</p>
        <details class="scholium-callout scholium-callout-flag" open>
          <summary><span class="scholium-callout-role">Caution</span><span class="scholium-callout-title scholium-callout-default-title">Caution</span></summary>
          <p>Nested 原文</p>
        </details>
      </aside>
    </div></body></html>`);
    const root = document.querySelector<HTMLElement>("#root")!;
    localizeRenderedInterface(root, localize);
    expect(root.querySelector(".scholium-callout-state > header > .scholium-callout-role")?.textContent).toBe("论点");
    expect(root.querySelector(".scholium-callout-state > header > .scholium-callout-role")?.getAttribute("aria-label"))
      .toBe("论点。呈现论点，而不表示认可。");
    expect(root.querySelector(".scholium-callout-state > header > .scholium-callout-role")?.getAttribute("title"))
      .toBe("呈现论点，而不表示认可。");
    expect(root.querySelector(".scholium-callout-state > header > .scholium-callout-title")?.textContent).toBe("Authored 标题");
    expect(root.querySelector(".scholium-callout-default-title")?.textContent).toBe("限定");
    expect([...root.querySelectorAll("p")].map(element => element.textContent)).toEqual(["Exact é quoted source.", "Nested 原文"]);
    expect(root.querySelector("details")?.hasAttribute("open")).toBe(true);
    const firstProjection = root.innerHTML;
    localizeRenderedInterface(root, localize);
    expect(root.innerHTML).toBe(firstProjection);
  });

  it("localizes footnote, task and table names while retaining identities, states and text", () => {
    const {document} = parseHTML(`<html><body><div id="root">
      <button class="footnote-reference" data-footnote="2" aria-expanded="true">2</button>
      <section class="footnotes"><p>Exact original footnote.</p><button class="footnote-return" data-footnote="2">↩</button></section>
      <input class="scholium-task-checkbox" checked disabled><input class="scholium-task-checkbox" disabled>
      <table class="scholium-table"><tr><td>Authored header</td></tr></table>
      <button data-link-annotation="annotation-1" data-link-annotation-target="Authored 理由" aria-expanded="true"></button>
    </div></body></html>`);
    const root = document.querySelector<HTMLElement>("#root")!;
    const inputs = root.querySelectorAll<HTMLInputElement>("input");
    // Linkedom does not expose checked; mirror the browser's native state for this DOM proof.
    Object.defineProperty(inputs[0], "checked", {value: true});
    Object.defineProperty(inputs[1], "checked", {value: false});
    localizeRenderedInterface(root, localize);
    expect(root.querySelector(".footnote-reference")?.getAttribute("aria-label")).toBe("脚注 2");
    expect(root.querySelector(".footnote-reference")?.getAttribute("aria-expanded")).toBe("true");
    expect(root.querySelector(".footnote-return")?.getAttribute("aria-label")).toBe("返回脚注 2 的引用处");
    expect(root.querySelector(".footnotes")?.getAttribute("aria-label")).toBe("脚注");
    expect(root.querySelector(".footnotes p")?.textContent).toBe("Exact original footnote.");
    expect(inputs[0].getAttribute("aria-label")).toBe("已完成的任务");
    expect(inputs[1].getAttribute("aria-label")).toBe("未完成的任务");
    expect(inputs[0].hasAttribute("checked")).toBe(true);
    expect(inputs[0].hasAttribute("disabled")).toBe(true);
    expect(root.querySelector("table")?.getAttribute("aria-label")).toBe("Markdown 表格");
    expect(root.querySelector("td")?.textContent).toBe("Authored header");
    expect(root.querySelector("button[data-link-annotation]")?.getAttribute("aria-label"))
      .toBe("隐藏“Authored 理由”的链接注释");
    expect(root.querySelector("button[data-link-annotation]")?.getAttribute("aria-expanded")).toBe("true");
  });
});

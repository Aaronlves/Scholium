import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createLiveInlineWidgets} from "../live-inline-widgets";

const widgets = createLiveInlineWidgets({
  requestMathRuntime() {},
  didToggleTask() {},
});

describe("live inline widget presentation", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("projects multiline Markdown behind one accessible annotation disclosure", () => {
    const {document} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    const dom = widgets.linkAnnotation("Reason one.\n\n- Reason two", "Target").toDOM();
    const button = dom.querySelector<HTMLButtonElement>("button")!;
    const template = dom.querySelector<HTMLTemplateElement>("template")!;
    expect(dom.tagName).toBe("SUP");
    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(button.getAttribute("aria-controls")).toBe("scholium-preview-popover");
    expect(button.dataset.linkAnnotationTarget).toBe("Target");
    expect(template.content.querySelector(".scholium-link-annotation-content")?.textContent)
      .toContain("Reason two");
    expect(dom.querySelector(".scholium-link-annotation-panel")).toBeNull();
  });

  it("derives nested list indentation from the shared semantic variable", () => {
    expect(widgets.listIndent(0)).toBe("");
    expect(widgets.listIndent(2)).toBe(
      "calc(var(--scholium-list-indent) + var(--scholium-list-indent))",
    );
  });
});

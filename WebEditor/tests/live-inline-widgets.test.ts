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
    const panel = dom.querySelector<HTMLElement>("[role=note]")!;
    expect(button.getAttribute("aria-expanded")).toBe("false");
    expect(panel.hidden).toBe(true);
    button.click();
    expect(button.getAttribute("aria-expanded")).toBe("true");
    expect(panel.hidden).toBe(false);
    expect(panel.textContent).toContain("Reason two");
  });

  it("derives nested list indentation from the shared semantic variable", () => {
    expect(widgets.listIndent(0)).toBe("");
    expect(widgets.listIndent(2)).toBe(
      "calc(var(--scholium-list-indent) + var(--scholium-list-indent))",
    );
  });
});

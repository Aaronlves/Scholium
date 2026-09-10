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
    expect(button.getAttribute("aria-controls")).toBeNull();
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

  it("returns a rendered formula to its exact source boundary on pointer input", () => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    window.scholiumMath = {
      version: 1,
      render: () => ({ok: true as const, html: "<span class='katex'>x</span>"}),
    };
    const dispatch = vi.fn();
    const focus = vi.fn();
    const view = {
      composing: false,
      state: {doc: {length: 32}},
      dispatch,
      focus,
    } as unknown as import("@codemirror/view").EditorView;
    const expression = {
      kind: "inline" as const,
      content: "x",
      delimiterLength: 1,
      from: 12,
      to: 17,
      contentFrom: 13,
      contentTo: 14,
    };
    const element = widgets.math(expression).toDOM(view) as HTMLElement;
    element.getBoundingClientRect = () => ({left: 0, width: 100} as DOMRect);
    const event = document.createEvent("Event") as unknown as MouseEvent;
    event.initEvent("mousedown", true, true);
    Object.defineProperties(event, {
      button: {value: 0},
      clientX: {value: 80},
    });
    element.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
    expect(dispatch).toHaveBeenCalledWith({
      selection: {anchor: 17},
      scrollIntoView: true,
    });
    expect(focus).toHaveBeenCalledOnce();
    expect(element.dataset.scholiumSourceFrom).toBe("12");
    expect(element.dataset.scholiumSourceTo).toBe("17");
  });
});

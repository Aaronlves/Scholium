import {parseHTML} from "linkedom";
import {EditorState} from "@codemirror/state";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";
import {createLiveInlineWidgets} from "../live-inline-widgets";
import {awaitVisibleDocumentWidgets, mathRuntimeSettledEvent} from "../document-widget-readiness";
import {renderPreviewMathNodes} from "../preview-popover";

const widgets = createLiveInlineWidgets({
  requestMathRuntime() {},
  didToggleTask() {},
});

describe("live inline widget presentation", () => {
  // Linkedom's window is a proxy over the test global. Runtime availability
  // belongs to each fixture; a previous fixture's installation must not leak.
  beforeEach(() => vi.stubGlobal("scholiumMath", undefined));
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

  it("rebuilds a formula widget when its requested runtime arrives", () => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const expression = {
      kind: "inline" as const,
      content: "x",
      delimiterLength: 1,
      from: 0,
      to: 3,
      contentFrom: 1,
      contentTo: 2,
    };
    const awaitingRuntime = widgets.math(expression, "$x$");
    expect(awaitingRuntime.toDOM({} as import("@codemirror/view").EditorView)
      .classList.contains("scholium-math-error")).toBe(true);
    window.scholiumMath = {
      version: 1,
      render: () => ({ok: true as const, html: "<span class='katex'>x</span>"}),
    };
    const ready = widgets.math(expression, "$x$");
    expect(awaitingRuntime.eq(ready)).toBe(false);
    expect(ready.toDOM({} as import("@codemirror/view").EditorView)
      .classList.contains("scholium-math-rendered")).toBe(true);
  });

  it.each(["rendered", "unavailable"])("settles opening mathematics only after its %s presentation is final", async result => {
    const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const root = document.getElementById("root")!;
    const rect = () => ({left: 0, right: 300, top: 0, bottom: 200} as DOMRect);
    root.getBoundingClientRect = rect;
    const expression = {kind: "display" as const, content: "x", delimiterLength: 2,
      from: 0, to: 5, contentFrom: 2, contentTo: 3};
    const pendingWidget = widgets.math(expression, "$$x$$");
    const dom = pendingWidget.toDOM({} as import("@codemirror/view").EditorView);
    dom.querySelector<HTMLElement>(".scholium-math")!.getBoundingClientRect = rect;
    root.append(dom);
    let ready = false;
    const pending = awaitVisibleDocumentWidgets(root, root, () => {}).then(() => { ready = true; });
    await Promise.resolve();
    expect(ready).toBe(false);
    if (result === "rendered") {
      window.scholiumMath = {version: 1, render: () => ({ok: true, html: "<span>x</span>"})};
      const next = widgets.math(expression, "$$x$$").toDOM({} as import("@codemirror/view").EditorView);
      dom.replaceWith(next);
      pendingWidget.destroy(dom);
    }
    window.dispatchEvent(new window.Event(mathRuntimeSettledEvent));
    await pending;
    expect(root.querySelector(result === "rendered" ? ".scholium-math-rendered" : ".scholium-math-source"))
      .not.toBeNull();
    if (result === "unavailable") expect(root.textContent).toBe("$$x$$");
  });

  it("includes source-backed Embedded Note mathematics in the same viewport barrier", async () => {
    const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const root = document.getElementById("root")!;
    const rect = () => ({left: 0, right: 300, top: 0, bottom: 200} as DOMRect);
    root.getBoundingClientRect = rect;
    const widget = widgets.embeddedNote({from: 0, to: 9, title: "Embedded", isEmbedded: true,
      htmlBody: "<span class='scholium-math' data-math-source='eA==' data-math-kind='inline'><code class='scholium-math-source'>$x$</code></span>"}, "Embedded", 0);
    const dom = widget.toDOM();
    dom.querySelector<HTMLElement>(".scholium-math")!.getBoundingClientRect = rect;
    root.append(dom);
    let ready = false;
    const pending = awaitVisibleDocumentWidgets(root, root, () => {}).then(() => { ready = true; });
    await Promise.resolve();
    expect(ready).toBe(false);
    window.scholiumMath = {version: 1, render: () => ({ok: true, html: "<span>x</span>"})};
    renderPreviewMathNodes(root);
    window.dispatchEvent(new window.Event(mathRuntimeSettledEvent));
    await pending;
    expect(dom.querySelector(".scholium-math-rendered")).not.toBeNull();
    expect(dom.querySelector(".scholium-math-source")?.textContent).toBe("$x$");
    widget.destroy(dom);
  });

  it("cancels a removed formula's pending runtime without waiting for its installation", async () => {
    const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const root = document.getElementById("root")!;
    const rect = () => ({left: 0, right: 300, top: 0, bottom: 200} as DOMRect);
    root.getBoundingClientRect = rect;
    const widget = widgets.math({kind: "inline", content: "x", delimiterLength: 1,
      from: 0, to: 3, contentFrom: 1, contentTo: 2}, "$x$");
    const dom = widget.toDOM({} as import("@codemirror/view").EditorView);
    dom.getBoundingClientRect = rect;
    root.append(dom);
    const pending = awaitVisibleDocumentWidgets(root, root, () => {});
    widget.destroy(dom);
    expect(await pending).toBe(true);
    expect(root.textContent).toBe("$x$");
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
      state: EditorState.create({doc: " ".repeat(32)}),
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
    const element = widgets.math(expression, "$ x $").toDOM(view) as HTMLElement;
    element.getBoundingClientRect = () => ({left: 0, width: 100} as DOMRect);
    const event = document.createEvent("Event") as unknown as MouseEvent;
    event.initEvent("mousedown", true, true);
    Object.defineProperties(event, {
      button: {value: 0},
      clientX: {value: 80},
    });
    element.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
    expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({
      scrollIntoView: true,
    }));
    expect(dispatch.mock.calls[0][0].selection.main).toMatchObject({anchor: 17, head: 17});
    expect(focus).toHaveBeenCalledOnce();
    expect(element.dataset.scholiumSourceFrom).toBe("12");
    expect(element.dataset.scholiumSourceTo).toBe("17");
  });

  it.each([
    {kind: "math", modifier: "Shift"}, {kind: "list", modifier: "Shift"},
    {kind: "math", modifier: "Command"}, {kind: "list", modifier: "Command"},
  ])("preserves existing ranges when $modifier-clicking a $kind projection", ({kind, modifier}) => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const source = "Before.\n\n- Item\n\n$ x $\n\nAfter.";
    let state = EditorState.create({doc: source, selection: {anchor: 2, head: 5},
      extensions: [EditorState.allowMultipleSelections.of(true)]});
    const dispatch = vi.fn(spec => { state = state.update(spec).state; });
    const view = {
      get state() { return state; }, compositionStarted: false, dispatch, focus: vi.fn(),
    } as unknown as import("@codemirror/view").EditorView;
    const mathFrom = source.indexOf("$"), mathTo = mathFrom + 5, markerFrom = source.indexOf("-");
    const element = kind === "math"
      ? widgets.math({kind: "inline", content: "x", delimiterLength: 1,
          from: mathFrom, to: mathTo, contentFrom: mathFrom + 1, contentTo: mathTo - 1}, "$ x $").toDOM(view)
      : widgets.listMarker({marker: "-", markerFrom, markerTo: markerFrom + 1, ordered: false, depth: 0,
          task: false, taskMarkerFrom: null, taskMarkerTo: null, taskChecked: false}).toDOM(view);
    element.getBoundingClientRect = () => ({left: 0, width: 100} as DOMRect);
    const event = document.createEvent("Event") as unknown as MouseEvent;
    event.initEvent("mousedown", true, true);
    Object.defineProperties(event, {button: {value: 0}, clientX: {value: 80},
      shiftKey: {value: modifier === "Shift"}, metaKey: {value: modifier === "Command"}});
    element.dispatchEvent(event);

    const head = kind === "math" ? mathTo : markerFrom;
    expect(state.selection.ranges.map(range => [range.anchor, range.head]))
      .toEqual(modifier === "Shift" ? [[2, head]] : [[2, 5], [head, head]]);
    expect(state.doc.toString()).toBe(source);
    expect(dispatch.mock.calls[0][0].annotations.value).toBe("select.pointer");
  });

  it.each(["math", "list", "task"])("leaves %s input alone from composition start before its first edit", kind => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const dispatch = vi.fn(), focus = vi.fn();
    const source = "- [ ] Item\n\n$x$";
    const view = {state: EditorState.create({doc: source}), composing: false, compositionStarted: true,
      dispatch, focus} as unknown as import("@codemirror/view").EditorView;
    const element = kind === "math"
      ? widgets.math({kind: "inline", content: "x", delimiterLength: 1,
          from: 12, to: 15, contentFrom: 13, contentTo: 14}, "$x$").toDOM(view)
      : widgets.listMarker({marker: "-", markerFrom: 0, markerTo: 1, ordered: false, depth: 0,
          task: kind === "task", taskMarkerFrom: 2, taskMarkerTo: 5, taskChecked: false}).toDOM(view);
    const target = kind === "task" ? element.querySelector("input")! : element;
    const event = document.createEvent("Event") as unknown as MouseEvent;
    event.initEvent(kind === "task" ? "click" : "mousedown", true, true);
    Object.defineProperty(event, "button", {value: 0});
    target.dispatchEvent(event);

    expect(dispatch).not.toHaveBeenCalled();
    expect(focus).not.toHaveBeenCalled();
    expect(view.state.doc.toString()).toBe(source);
  });

  it.each([
    {kind: "inline" as const, source: "$  \\invalid  $", delimiterLength: 1},
    {kind: "display" as const, source: "$$\n\n\\invalid\n\n$$", delimiterLength: 2},
  ])("retains exact $kind mathematics source when rendering fails", ({kind, source, delimiterLength}) => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    window.scholiumMath = {
      version: 1,
      render: () => ({ok: false as const, reason: "invalid-source" as const}),
    };
    const expression = {kind, source, content: "\\invalid", delimiterLength,
      from: 0, to: source.length, contentFrom: delimiterLength, contentTo: source.length - delimiterLength};
    const dom = widgets.math(expression, source).toDOM({} as import("@codemirror/view").EditorView);
    expect(dom.querySelector(".scholium-math-source")?.textContent).toBe(source);
  });

  it("replaces reused formula widgets when source whitespace or click coordinates change", () => {
    const {window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("window", window);
    const source = "$$\n\nx\n$$";
    const expression = {kind: "display" as const, content: "x", delimiterLength: 2,
      from: 0, to: source.length, contentFrom: 3, contentTo: source.length - 2};
    const original = widgets.math(expression, source);
    expect(original.eq(widgets.math(expression, "$$\nx\n\n$$"))).toBe(false);
    expect(original.eq(widgets.math({...expression, from: 5, to: source.length + 5}, source))).toBe(false);
    expect(original.eq(widgets.math({...expression}, source))).toBe(true);
  });
});

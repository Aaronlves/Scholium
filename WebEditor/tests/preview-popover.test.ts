import {EditorState, type TransactionSpec} from "@codemirror/state";
import type {EditorView} from "@codemirror/view";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {footnotePresentation} from "../footnote-presentation";
import type {NativePreviewSurface} from "../native-floating";
import {createPreviewPopoverController} from "../preview-popover";
import type {LinkPreview} from "../previews";

// Exercise the real controller and DOM listeners without pretending that this
// synthetic view proves native WebKit focus or CodeMirror pointer delivery.
vi.mock("@codemirror/view", async importOriginal => ({
  ...await importOriginal<typeof import("@codemirror/view")>(),
  ViewPlugin: {define: (mount: (view: EditorView) => unknown) => ({mount})},
}));

function fixture(source = "[[A]] and [[B]]", previews: LinkPreview[] = [
  {from: 0, to: 5, title: "A", isEmbedded: false, htmlBody: "<p>Content A</p>"},
]) {
  vi.useFakeTimers();
  const {document, window} = parseHTML("<html><body><div id='editor'></div><div id='scroll'></div></body></html>");
  vi.stubGlobal("document", document);
  vi.stubGlobal("Element", window.Element);
  vi.stubGlobal("Node", window.Node);
  vi.stubGlobal("window", {
    setTimeout, clearTimeout,
    requestAnimationFrame: (callback: FrameRequestCallback) => setTimeout(() => callback(0), 0),
    addEventListener: vi.fn(), removeEventListener: vi.fn(),
  });
  const contentDOM = document.getElementById("editor")!;
  let current: Omit<NativePreviewSurface, "id"> | null = null;
  let callbacks: {enter?(): void; leave?(): void; dismiss(): void} | null = null;
  let serial = 0;
  const nativeFloating = {
    show: vi.fn((surface: Omit<NativePreviewSurface, "id">, value: typeof callbacks) => {
      current = surface; callbacks = value; return ++serial;
    }),
    hide: vi.fn((id: number) => { if (id === serial) current = null; }),
  };
  const view = {
    state: EditorState.create({doc: source}), composing: false,
    contentDOM, scrollDOM: document.getElementById("scroll")!,
    coordsAtPos: vi.fn(() => ({left: 20, right: 21, top: 30, bottom: 44})),
    dispatch: vi.fn((spec: TransactionSpec) => { view.state = view.state.update(spec).state; }),
    focus: vi.fn(),
  };
  const controller = createPreviewPopoverController({
    nativeFloating, previews: () => previews,
    footnotes: () => footnotePresentation(view.state.doc.toString()),
    holdOpenForPerformancePreview: () => false,
    renderFootnoteContent: (content, parent) => { parent.textContent = content; },
  });
  const plugin = (controller.extension as unknown as {
    mount(view: EditorView): {destroy(): void};
  }).mount(view as unknown as EditorView);
  const anchors = (markup: string) => {
    contentDOM.innerHTML = markup;
    contentDOM.querySelectorAll<HTMLElement>("*").forEach(node => {
      node.getBoundingClientRect = () => ({left: 20, right: 50, top: 30, bottom: 44}) as DOMRect;
    });
  };
  const dispatch = (type: string, target: Element, fields: Record<string, unknown> = {}) => {
    const event = new window.Event(type, {bubbles: true, cancelable: true});
    Object.assign(event, {button: 0, detail: 1, metaKey: false, ctrlKey: false,
      isComposing: false, keyCode: 0}, fields);
    target.dispatchEvent(event);
    return event;
  };
  return {controller, view, nativeFloating, contentDOM, anchors, dispatch,
    current: () => current, enter: () => callbacks?.enter?.(), leave: () => callbacks?.leave?.(),
    close: () => plugin.destroy()};
}

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("editor preview target lifecycle", () => {
  it("dismisses A immediately when a projected B has no preview", () => {
    const f = fixture();
    f.anchors("<span data-link-preview-index='0'>A</span><span data-scholium-link-target='B' data-scholium-source-from='10' data-scholium-source-to='15'>B</span>");
    const [a, b] = f.contentDOM.children;
    f.dispatch("pointermove", a, {metaKey: true});
    vi.advanceTimersByTime(300);
    expect(f.current()?.html).toContain("Content A");
    f.dispatch("pointermove", b, {metaKey: true});
    expect(f.current()).toBeNull();
    vi.advanceTimersByTime(300);
    expect(f.current()).toBeNull();
    f.close();
  });

  it("does not postpone disclosure or reload the same target while the pointer moves", () => {
    const f = fixture();
    f.anchors("<span data-link-preview-index='0'>A</span>");
    const a = f.contentDOM.firstElementChild!;
    f.dispatch("pointermove", a, {metaKey: true});
    vi.advanceTimersByTime(200);
    f.dispatch("pointermove", a, {metaKey: true});
    vi.advanceTimersByTime(100);
    expect(f.current()?.html).toContain("Content A");
    f.dispatch("pointermove", a, {metaKey: true});
    vi.advanceTimersByTime(300);
    expect(f.nativeFloating.show).toHaveBeenCalledOnce();
    f.close();
  });

  it("allows releasing Command while reading inside the native preview", () => {
    const f = fixture();
    f.anchors("<span data-link-preview-index='0'>A</span>");
    const a = f.contentDOM.firstElementChild!;
    f.dispatch("pointermove", a, {metaKey: true});
    vi.advanceTimersByTime(300);
    f.enter();
    f.dispatch("keyup", a, {key: "Meta"});
    expect(f.current()?.html).toContain("Content A");
    f.leave();
    vi.advanceTimersByTime(180);
    expect(f.current()).toBeNull();
    f.close();
  });

  it("trusts current pointer modifiers after key-up occurred in another window", () => {
    const f = fixture();
    f.anchors("<span data-link-preview-index='0'>A</span>");
    const a = f.contentDOM.firstElementChild!;
    f.dispatch("pointermove", a);
    f.dispatch("keydown", a, {key: "Meta", metaKey: true});
    vi.advanceTimersByTime(300);
    expect(f.current()?.html).toContain("Content A");
    f.enter();
    // No key-up event reaches the document while the native window receives it.
    f.leave();
    f.dispatch("pointermove", a);
    vi.advanceTimersByTime(180);
    expect(f.current()).toBeNull();
    expect(a.classList.contains("scholium-link-preview-armed")).toBe(false);
    f.close();
  });

  it("projects menu availability from the same current target as disclosure", () => {
    const f = fixture();
    expect(f.controller.canShowAtSelection()).toBe(true);
    expect(f.controller.showAtSelection()).toBe(true);
    f.view.state = f.view.state.update({selection: {anchor: 10}}).state;
    expect(f.controller.canShowAtSelection()).toBe(false);
    expect(f.controller.showAtSelection()).toBe(false);
    expect(f.current()).toBeNull();
    f.view.state = f.view.state.update({selection: {anchor: 0}}).state;
    f.view.composing = true;
    expect(f.controller.canShowAtSelection()).toBe(false);
    expect(f.controller.showAtSelection()).toBe(false);
    f.close();
  });
});

describe("complete footnote preview and explicit source activation", () => {
  const content = "完整旁注 😀 é ".repeat(250) + " COMPLETE TAIL";

  it.each([false, true])("keeps the tail and source for a long footnote (inline=%s)", inline => {
    const source = inline ? `Claim^[${content}].` : `Claim[^note].\n\n[^note]: ${content}\n`;
    const f = fixture(source, []);
    const reference = footnotePresentation(source).references[0];
    f.view.state = f.view.state.update({selection: {anchor: reference.from}}).state;
    expect(f.controller.canShowAtSelection()).toBe(true);
    expect(f.controller.showAtSelection()).toBe(true);
    expect(f.current()?.html).toContain("COMPLETE TAIL");
    expect(f.view.state.doc.toString()).toBe(source);
    f.close();
  });

  it.each([0, 1])("navigates the current exact definition on explicit click (detail=%s)", detail => {
    const source = "Claim[^note].\n\n[^note]: Exact definition.\n";
    const f = fixture(source, []);
    f.anchors("<span class='cm-live-footnote-reference-widget'><button class='footnote-reference' data-footnote-identifier='note' data-footnote-occurrence='1'>1</button></span>");
    const button = f.contentDOM.querySelector("button")!;
    f.dispatch("focusin", button);
    expect(f.current()?.html).toContain("Exact definition.");
    f.dispatch("click", button, {detail});
    expect(f.view.state.selection.main.head).toBe(source.indexOf("Exact definition."));
    expect(f.view.focus).toHaveBeenCalledOnce();
    expect(f.current()).toBeNull();
    expect(f.view.state.doc.toString()).toBe(source);
    f.close();
  });

  it("keeps mouse-down out of text selection and activates only on click", () => {
    const source = "Claim^[Exact inline content].";
    const f = fixture(source, []);
    f.anchors("<span class='cm-live-footnote-reference-widget'><button class='footnote-reference' data-footnote-identifier='inline-1' data-footnote-occurrence='1'>1</button></span>");
    const button = f.contentDOM.querySelector("button")!;
    expect(f.dispatch("mousedown", button).defaultPrevented).toBe(true);
    expect(f.view.dispatch).not.toHaveBeenCalled();
    f.dispatch("click", button);
    expect(f.view.state.selection.main.head).toBe(source.indexOf("Exact inline content"));
    f.close();
  });
});

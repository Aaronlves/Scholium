import {EditorState, StateEffect, type TransactionSpec} from "@codemirror/state";
import {EditorView, type WidgetType} from "@codemirror/view";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {scholiumNoteLanguage} from "../language";
import {createLiveMermaidProjection} from "../live-mermaid-projection";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSelectionController} from "../live-selection";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";
import {awaitVisibleDocumentWidgets} from "../document-widget-readiness";
import type {ScholiumMermaidRuntime, ScholiumMermaidRenderResult} from "../mermaid-runtime";

function mermaidHarness(runtime: Promise<ScholiumMermaidRuntime | null> = new Promise(() => {})) {
  const selection = createLiveSelectionController({
    handleModifiedLink: () => false, handleProjectedPointerStart: () => false,
  });
  const projections = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
  const widgets = createProjectedWidgetRegistry();
  const theme = StateEffect.define<number>();
  const ensureRuntime = vi.fn(() => runtime);
  const mermaids = createLiveMermaidProjection({selection, projections, widgets, ensureRuntime,
    currentThemeRevision: () => 0, refreshThemeEffect: theme});
  let state = EditorState.create({doc: "Before.\n\n```mermaid\nflowchart LR\nA --> B\n```\n\nAfter.", extensions: [
    scholiumNoteLanguage, selection.extension, projections.extension, mermaids.extension,
  ]});
  const view = {get state() { return state; }, requestMeasure: vi.fn()} as unknown as EditorView;
  return {
    view, widgets, theme, ensureRuntime,
    update(spec: TransactionSpec) { state = state.update(spec).state; },
    widget() {
      let widget: WidgetType | undefined;
      for (const decorations of state.facet(EditorView.decorations)) {
        if (typeof decorations === "function") continue;
        decorations.between(0, state.doc.length, (_from, _to, decoration) => {
          if (decoration.spec.widget) widget = decoration.spec.widget;
        });
      }
      if (!widget) throw new Error("Expected a projected Mermaid diagram.");
      return widget;
    },
  };
}

describe("Mermaid pointer source mapping", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("updates reused diagram coordinates after preceding edits without rerendering", () => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    vi.stubGlobal("Element", window.Element);
    const harness = mermaidHarness();
    const previous = harness.widget();
    const dom = previous.toDOM(harness.view);
    const oldContentFrom = harness.widgets.mermaid(dom)!.contentFrom;
    harness.update({changes: {from: 0, insert: "Prefix.\n\n"}});
    const current = harness.widget();

    expect(current.eq(previous)).toBe(false);
    expect(current.updateDOM(dom, harness.view, previous)).toBe(true);
    expect(harness.widgets.sourceOffset({target: dom} as unknown as MouseEvent))
      .toBe(oldContentFrom + "Prefix.\n\n".length);
    expect(harness.ensureRuntime).toHaveBeenCalledOnce();
    expect(dom.querySelector("code")?.textContent).toContain("flowchart LR");
  });

  it("does not reuse diagram rendering across a theme or authored source change", () => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const harness = mermaidHarness();
    const previous = harness.widget();
    const dom = previous.toDOM(harness.view);
    harness.update({effects: harness.theme.of(1)});
    expect(harness.widget().updateDOM(dom, harness.view, previous)).toBe(false);
    const changedFrom = harness.view.state.doc.toString().indexOf("A --> B");
    harness.update({changes: {from: changedFrom, to: changedFrom + 7, insert: "A --> C"}});
    expect(harness.widget().updateDOM(dom, harness.view, previous)).toBe(false);
  });

  it("keeps visible Mermaid pending until actual rendering is mounted", async () => {
    const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    let finishRender!: (result: ScholiumMermaidRenderResult) => void;
    const runtime: ScholiumMermaidRuntime = {
      version: 3,
      copy: () => null,
      render: vi.fn(() => new Promise<ScholiumMermaidRenderResult>(resolve => { finishRender = resolve; })),
      mount: (host, svg) => { host.append(svg); return true; },
    };
    const harness = mermaidHarness(Promise.resolve(runtime));
    const widget = harness.widget();
    const dom = widget.toDOM(harness.view);
    const root = document.getElementById("root")!;
    const rect = () => ({left: 0, right: 300, top: 0, bottom: 200} as DOMRect);
    root.getBoundingClientRect = dom.getBoundingClientRect = rect;
    root.append(dom);
    let ready = false;
    const pending = awaitVisibleDocumentWidgets(root, root, () => {}).then(() => { ready = true; });
    await Promise.resolve();
    expect(ready).toBe(false);
    expect(dom.querySelector(".scholium-mermaid-output")).toBeNull();
    finishRender({ok: true, kind: "flowchart", accessibilityWarning: false,
      svg: document.createElementNS("http://www.w3.org/2000/svg", "svg") as SVGSVGElement});
    await pending;
    expect(dom.querySelector(".scholium-mermaid-output svg")).not.toBeNull();
    expect(harness.view.requestMeasure).toHaveBeenCalled();
  });

  it("settles unavailable Mermaid at its existing source fallback", async () => {
    const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const harness = mermaidHarness(Promise.resolve(null));
    const dom = harness.widget().toDOM(harness.view);
    const root = document.getElementById("root")!;
    const rect = () => ({left: 0, right: 300, top: 0, bottom: 200} as DOMRect);
    root.getBoundingClientRect = dom.getBoundingClientRect = rect;
    root.append(dom);
    expect(await awaitVisibleDocumentWidgets(root, root, () => {})).toBe(true);
    expect(dom.querySelector(".scholium-mermaid-source code")?.textContent).toContain("A --> B");
    expect(dom.querySelector(".scholium-mermaid-error")).not.toBeNull();
  });

  it("cancels destroyed Mermaid without waiting for an unresolved runtime", async () => {
    const {document, window} = parseHTML("<html><body><div id='root'></div></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    const harness = mermaidHarness();
    const widget = harness.widget();
    const dom = widget.toDOM(harness.view);
    const root = document.getElementById("root")!;
    const rect = () => ({left: 0, right: 300, top: 0, bottom: 200} as DOMRect);
    root.getBoundingClientRect = dom.getBoundingClientRect = rect;
    root.append(dom);
    const pending = awaitVisibleDocumentWidgets(root, root, () => {});
    widget.destroy(dom);
    expect(await pending).toBe(true);
    expect(dom.querySelector(".scholium-mermaid-source code")?.textContent).toContain("A --> B");
  });
});

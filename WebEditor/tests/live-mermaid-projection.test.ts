import {EditorState, StateEffect, type TransactionSpec} from "@codemirror/state";
import {EditorView, type WidgetType} from "@codemirror/view";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {scholiumNoteLanguage} from "../language";
import {createLiveMermaidProjection} from "../live-mermaid-projection";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSelectionController} from "../live-selection";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";

function mermaidHarness() {
  const selection = createLiveSelectionController({
    handleModifiedLink: () => false, handleProjectedPointerStart: () => false,
  });
  const projections = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
  const widgets = createProjectedWidgetRegistry();
  const theme = StateEffect.define<number>();
  const ensureRuntime = vi.fn(() => new Promise<null>(() => {}));
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
});

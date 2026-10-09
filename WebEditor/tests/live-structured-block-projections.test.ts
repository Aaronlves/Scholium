import {EditorState, type Transaction, type TransactionSpec} from "@codemirror/state";
import {EditorView, type WidgetType} from "@codemirror/view";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createLiveSelectionController} from "../live-selection";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveStructuredBlockProjections} from "../live-structured-block-projections";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";
import {preserveLivePresentationLayout} from "../live-presentation-layout";
import {scholiumNoteLanguage} from "../language";

function headingWidget(state: EditorState) {
  let result: WidgetType | undefined;
  for (const decorations of state.facet(EditorView.decorations)) {
    if (typeof decorations === "function") continue;
    decorations.between(0, state.doc.length, (_from, _to, decoration) => {
      if (decoration.spec.widget) result = decoration.spec.widget;
    });
  }
  if (!result) throw new Error("Missing Callout heading widget");
  return result;
}

function calloutHarness() {
  const {document} = parseHTML("<html><body></body></html>");
  vi.stubGlobal("document", document);
  const selection = createLiveSelectionController({
    handleModifiedLink: () => false, handleProjectedPointerStart: () => false,
  });
  const projections = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
  const blocks = createLiveStructuredBlockProjections({selection, projections,
    widgets: createProjectedWidgetRegistry(), editingDialect: () => null, reuseCounts: {table: 0}});
  let state = EditorState.create({doc: "Lead\n\n> [!state]+ Heading\n> Body\n\nAfter",
    extensions: [scholiumNoteLanguage, selection.extension, projections.extension, blocks.calloutExtension]});
  const transactions: Transaction[] = [];
  const dispatch = vi.fn((spec: TransactionSpec) => {
    const transaction = state.update(spec);
    transactions.push(transaction);
    state = transaction.state;
  });
  const view = {get state() {return state;}, composing: false, compositionStarted: false, dispatch};
  const root = headingWidget(state).toDOM(view as unknown as EditorView);
  return {view, root, dispatch, transactions,
    change(spec: TransactionSpec) {state = state.update(spec).state;},
    click() {
      const event = document.createEvent("Event");
      event.initEvent("click", true, true);
      root.querySelector("button")!.dispatchEvent(event);
    },
  };
}

afterEach(() => vi.unstubAllGlobals());

describe("retained Callout disclosure", () => {
  it("folds and preserves layout using the current widget ranges after source shifts", () => {
    const h = calloutHarness();
    const previous = headingWidget(h.view.state);
    h.change({changes: {from: 0, insert: "Prelude.\n\n"}});
    expect(headingWidget(h.view.state).updateDOM(h.root, h.view as unknown as EditorView, previous)).toBe(true);
    const source = h.view.state.doc.toString();
    const from = source.indexOf("> [!state]");
    const bodyFrom = h.view.state.doc.lineAt(from).to;
    const foldTo = source.indexOf("\n\nAfter") + 1;
    h.click();
    expect(h.view.state.selection.main).toMatchObject({anchor: from, head: from});
    const layout = h.transactions[0].effects.find(effect => effect.is(preserveLivePresentationLayout));
    expect(layout?.value).toEqual({from: bodyFrom, to: foldTo});
    expect(h.view.state.doc.toString()).toBe(source);
  });

  it("does not fold or change selection after composition starts before its first edit", () => {
    const h = calloutHarness();
    h.view.compositionStarted = true;
    const before = h.view.state;
    h.click();
    expect(h.dispatch).not.toHaveBeenCalled();
    expect(h.view.state).toBe(before);
  });
});

import {Compartment, EditorSelection, EditorState, Prec, Transaction, type TransactionSpec} from "@codemirror/state";
import {history, redoDepth, undo} from "@codemirror/commands";
import {deleteMarkupBackward, insertNewlineContinueMarkup} from "@codemirror/lang-markdown";
import {EditorView, keymap} from "@codemirror/view";
import {describe, expect, it} from "vitest";
import {createMarkdownDocumentState} from "../bootstrap";
import {createDeferredEditingInfrastructure} from "../deferred-editing-infrastructure";
import {captureExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory} from "../exact-source-history";
import {continueCallout, continueList} from "../interaction";
import {scholiumNoteLanguage} from "../language";
import {normalizedDocumentText} from "../state";
import {citationHistory} from "../zotero-citation-state";

type Lifecycle = "initial Edit" | "cold Review" | "reconstructed Review";

function harness(source: string, lifecycle: Lifecycle, livePreview = false) {
  const mode = new Compartment();
  const infrastructure = createDeferredEditingInfrastructure(scholiumNoteLanguage);
  const cold = lifecycle !== "initial Edit";
  let label: string | undefined;
  const structuralEnter = (view: EditorView) => {
    if (view.state.readOnly || !view.state.facet(EditorView.editable)) return false;
    const selections = view.state.selection.ranges.map(({anchor, head}) => ({anchor, head}));
    const action = (livePreview ? continueCallout(view.state.doc, selections) : null)
      ?? continueList(view.state.doc, selections);
    if (!action) return false;
    view.dispatch({changes: action.changes,
      selection: EditorSelection.create(action.selections.map(({anchor, head}) => EditorSelection.range(anchor, head))),
      userEvent: "input.scholium.continueStructure"});
    label = action.undoLabel;
    return true;
  };
  let genericBackspace = 0;
  const extensions = [history(), exactSourceHistory, citationHistory, EditorState.lineSeparator.of("\n"),
    Prec.high(keymap.of([{key: "Enter", run: structuralEnter}])),
    // As in the editor, the retained language compartment follows the owning
    // high-precedence bindings and precedes generic editing fallbacks.
    infrastructure.forDocument(cold ? "review" : "source"),
    keymap.of([{key: "Backspace", run: () => { genericBackspace++; return true; }}]),
    mode.of(cold ? [EditorState.readOnly.of(true), EditorView.editable.of(false)] : [])];
  let state = createMarkdownDocumentState(source, extensions, {
    selection: EditorSelection.single(normalizedDocumentText(source).length),
  });
  const dispatch = (transaction: Transaction | TransactionSpec) => {
    state = transaction instanceof Transaction ? transaction.state : state.update(transaction).state;
  };
  const view = {get state() { return state; }, dispatch} as EditorView;
  if (lifecycle === "reconstructed Review") {
    const written = createMarkdownDocumentState(source, [history(), exactSourceHistory, citationHistory], {
      selection: state.selection,
    }).update({changes: {from: 0, insert: "x"}, userEvent: "input.type"}).state;
    let retained = written;
    expect(undo({state: written, dispatch: transaction => { retained = transaction.state; }})).toBe(true);
    state = restoreExactHistory(captureExactHistory(retained)!, source, extensions);
    expect(redoDepth(state)).toBe(1);
  }
  const originalHistory = captureExactHistory(state);
  if (cold) {
    expect(state.facet(keymap).flat().some(binding => binding.run === insertNewlineContinueMarkup)).toBe(false);
    // Match the production two-dispatch activation: dependencies first, then
    // writable mode, without moving the compartment in the extension order.
    dispatch({effects: infrastructure.activationEffects(state, "livePreview")});
    dispatch({effects: mode.reconfigure([]), annotations: Transaction.addToHistory.of(false)});
  }
  expect(captureExactHistory(state)).toBe(originalHistory);
  const bindings = state.facet(keymap).flat();
  expect(bindings.findIndex(binding => binding.run === structuralEnter))
    .toBeLessThan(bindings.findIndex(binding => binding.run === insertNewlineContinueMarkup));
  expect(bindings.some(binding => binding.run === deleteMarkupBackward)).toBe(true);
  return {
    view, label: () => label, genericBackspace: () => genericBackspace,
    run(key: string) {
      for (const binding of state.facet(keymap).flat()) {
        if (binding.key === key && binding.run?.(view)) return binding.run;
      }
      throw new Error(`Unhandled key: ${key}`);
    },
    structuralEnter,
  };
}

describe("deferred language keyboard precedence", () => {
  for (const lifecycle of ["initial Edit", "cold Review", "reconstructed Review"] as const) {
    it(`keeps Scholium list and Callout Return ahead of Markdown after ${lifecycle}`, () => {
      for (const [source, suffix, livePreview] of [
        ["- first\r\n- second", "\r\n- ", false],
        ["> [!state] Claims\n> - First claim", "\n> - ", true],
      ] as const) {
        const h = harness(source, lifecycle, livePreview);
        expect(h.run("Enter")).toBe(h.structuralEnter);
        expect(h.label()).toBe("Continue List");
        expect(h.view.state.field(exactSourceState).text).toBe(source + suffix);
        expect(undo({state: h.view.state, dispatch: h.view.dispatch})).toBe(true);
        expect(h.view.state.field(exactSourceState).text).toBe(source);
      }
    });

    it(`retains Markdown Backspace and its generic fallback after ${lifecycle}`, () => {
      const list = harness("- ", lifecycle);
      expect(list.run("Backspace")).toBe(deleteMarkupBackward);
      expect(list.view.state.field(exactSourceState).text).toBe("");
      expect(list.genericBackspace()).toBe(0);
      const prose = harness("Body", lifecycle);
      expect(prose.run("Backspace")).not.toBe(deleteMarkupBackward);
      expect(prose.genericBackspace()).toBe(1);
    });
  }
});

import {EditorState} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {describe, expect, it} from "vitest";
import {scholiumNoteLanguage} from "../language";
import {createLiveFootnoteProjection} from "../live-footnote-projection";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSelectionController} from "../live-selection";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";

function footnoteState(source: string) {
  const selection = createLiveSelectionController({
    handleModifiedLink: () => false,
    handleProjectedPointerStart: () => false,
  });
  const projections = createLiveProjectionIndexController({
    editingDialect: () => null,
    recordMetric: () => {},
  });
  const footnotes = createLiveFootnoteProjection({
    selection, projections, widgets: createProjectedWidgetRegistry(), reuseCounts: {footnote: 0},
  });
  return EditorState.create({doc: source, extensions: [
    scholiumNoteLanguage, selection.extension, projections.extension, footnotes.extension,
  ]});
}

function replacedSource(state: EditorState) {
  const sources: string[] = [];
  for (const decoration of state.facet(EditorView.decorations)) {
    if (typeof decoration === "function") continue;
    decoration.between(0, state.doc.length, (from, to, value) => {
      if (value.spec.widget) sources.push(state.doc.sliceString(from, to));
    });
  }
  return sources;
}

describe("live footnote source fallback", () => {
  it("keeps unresolved identifiers and their punctuation visible beside resolved references", () => {
    const source = "Missing[^absent]，known[^one].\n\n[^one]: Known definition.";
    const state = footnoteState(source);
    expect(replacedSource(state)).toEqual(["[^one]."]);
    expect(state.doc.toString()).toBe(source);
  });

  it("changes only presentation when an exact definition is added or removed", () => {
    const source = "Missing[^absent].";
    let state = footnoteState(source);
    expect(replacedSource(state)).toEqual([]);
    state = state.update({changes: {from: source.length, insert: "\n\n[^absent]: Found."}}).state;
    expect(replacedSource(state)).toEqual(["[^absent]."]);
    state = state.update({changes: {from: source.length, to: state.doc.length}}).state;
    expect(replacedSource(state)).toEqual([]);
    expect(state.doc.toString()).toBe(source);
  });
});

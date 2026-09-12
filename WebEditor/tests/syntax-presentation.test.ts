import {EditorState} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {describe, expect, it} from "vitest";
import {canDisplaceSyntax, prefixNeedsMargin, syntaxToken} from "../syntax-presentation";
import {createLiveSelectionController} from "../live-selection";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveStructuredBlockProjections} from "../live-structured-block-projections";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";
import {scholiumNoteLanguage} from "../language";

describe("syntax presentation boundaries", () => {
  it("borrows whitespace only for wrapping introduced by the prefix itself", () => {
    expect(prefixNeedsMargin(310, 20, 300, 40)).toBe(true);
    expect(prefixNeedsMargin(290, 20, 300, 40)).toBe(false);
    expect(prefixNeedsMargin(340, 20, 300, 40)).toBe(false);
    expect(prefixNeedsMargin(310, 20, 300, 20)).toBe(false);
  });
  it("limits displacement to short single-line tokens", () => {
    for (const token of ["**", "~~", "`", "###### ", "> "]) {
      expect(canDisplaceSyntax(token)).toBe(true);
    }
    for (const token of ["> [!cite] ", "```", "~~~", "(long-target.md)", "", "\t>", ">\n>", "中文", "x".repeat(25)]) {
      expect(canDisplaceSyntax(token)).toBe(false);
    }
  });

  it("keeps exposed source addressable and hidden source out of accessibility", () => {
    const hidden = syntaxToken("**", 4, 6, false);
    const exposed = syntaxToken("**", 4, 6, true);
    expect(hidden.spec.attributes["aria-hidden"]).toBe("true");
    expect(exposed.spec.attributes["aria-hidden"]).toBeUndefined();
    expect(hidden.spec.attributes["data-syntax-key"])
      .toBe(exposed.spec.attributes["data-syntax-key"]);
  });

  it("retains expanded callout prose across activation and preserves authored folding", () => {
    const selection = createLiveSelectionController({
      handleModifiedLink: () => false, handleProjectedPointerStart: () => false,
    });
    const projections = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    const blocks = createLiveStructuredBlockProjections({selection, projections,
      widgets: createProjectedWidgetRegistry(), editingDialect: () => null,
      reuseCounts: {table: 0}});
    for (const fold of ["", "+", "-"]) {
      const source = `Lead\n\n> [!cite]${fold} Source\n> **中文** evidence\n\nAfter`;
      let state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage,
        selection.extension, projections.extension, blocks.calloutExtension]});
      const replacements = () => {
        const ranges: number[][] = [];
        for (const decorations of state.facet(EditorView.decorations)) {
          if (typeof decorations === "function") continue;
          decorations.between(0, state.doc.length, (from, to) => { if (to > from) ranges.push([from, to]); });
        }
        return ranges;
      };
      expect(replacements().length).toBe(fold === "-" ? 1 : 0);
      state = state.update({selection: {anchor: source.indexOf("evidence")}}).state;
      expect(replacements()).toEqual([]);
      expect(state.doc.toString()).toBe(source);
    }
  });
});

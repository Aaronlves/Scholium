import {Range, StateField, type EditorState, type Extension} from "@codemirror/state";
import {Decoration, DecorationSet, EditorView, WidgetType} from "@codemirror/view";
import type {MathProjection} from "./math";
import {
  activeProjectionSignature,
  selectionIntersectsProjection,
  transactionChangedSyntaxTree,
} from "./projection-update";
import type {LiveProjectionIndexController} from "./live-projection-index";
import type {LiveSelectionController} from "./live-selection";

interface LiveDisplayMathProjectionState {
  readonly decorations: DecorationSet;
  readonly hasConstructs: boolean;
  readonly presentations: readonly MathProjection[];
}

export function createLiveDisplayMathProjection(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  widget(expression: MathProjection): WidgetType;
}): {extension: Extension} {
  function decorations(
    state: EditorState,
    presentations: readonly MathProjection[],
  ) {
    return Decoration.set(presentations.flatMap((presentation): Range<Decoration>[] => {
      const active = options.selection.selection(state).ranges.some((range) =>
        selectionIntersectsProjection(range, presentation));
      if (active) return [];
      return [Decoration.replace({
        widget: options.widget(presentation),
        block: true,
      }).range(presentation.from, presentation.to)];
    }), true);
  }

  function build(state: EditorState): LiveDisplayMathProjectionState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {decorations: Decoration.none, hasConstructs: true, presentations: []};
    }
    const presentations = index.mathExpressions.filter((expression) => expression.kind === "display");
    return {
      decorations: decorations(state, presentations),
      hasConstructs: presentations.length > 0,
      presentations,
    };
  }

  const field = StateField.define<LiveDisplayMathProjectionState>({
    create: build,
    update(previous, transaction) {
      if (transaction.docChanged || transactionChangedSyntaxTree(transaction)) {
        return build(transaction.state);
      }
      if (!options.selection.changed(transaction.startState, transaction.state)) return previous;
      if (activeProjectionSignature(
        options.selection.selection(transaction.startState).ranges,
        previous.presentations,
      ) === activeProjectionSignature(
        options.selection.selection(transaction.state).ranges,
        previous.presentations,
      )) return previous;
      return {
        ...previous,
        decorations: decorations(transaction.state, previous.presentations),
      };
    },
    provide: (field) => [
      EditorView.decorations.from(field, (value) => value.decorations),
      EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
    ],
  });

  return {extension: field};
}

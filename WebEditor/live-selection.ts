import {
  EditorSelection,
  Range,
  StateEffect,
  StateField,
  type EditorState,
  type Extension,
} from "@codemirror/state";
import {Decoration, EditorView, ViewPlugin} from "@codemirror/view";

type PointerProjectionPhase = "idle" | "deferred" | "immediate";

interface LiveProjectionSelectionState {
  readonly selection: EditorSelection;
  readonly pointerPhase: PointerProjectionPhase;
}

export interface LiveSelectionController {
  readonly extension: Extension;
  selection(state: EditorState): EditorSelection;
  changed(startState: EditorState, state: EditorState): boolean;
  interactionChanged(startState: EditorState, state: EditorState): boolean;
  pointerSelectionIsComplete(state: EditorState): boolean;
}

const selectedTextMark = Decoration.mark({class: "cm-scholium-selected-text"});

/**
 * CodeMirror's stock drawSelection layer paints rectangular continuation
 * areas across block boundaries. Scholium keeps EditorSelection authoritative
 * and marks only selected source characters on each physical line. These
 * marks cannot add geometry and deliberately omit line endings, authored
 * blank lines, widgets, padding, and semantic gaps.
 */
export const textSelectionPresentation = EditorView.decorations.compute(
  ["selection"],
  (state) => {
    const ranges: Range<Decoration>[] = [];
    for (const selection of state.selection.ranges) {
      if (selection.empty) continue;
      let line = state.doc.lineAt(selection.from);
      while (line.from <= selection.to) {
        const from = Math.max(selection.from, line.from);
        const to = Math.min(selection.to, line.to);
        if (to > from) ranges.push(selectedTextMark.range(from, to));
        if (line.number >= state.doc.lines || line.to >= selection.to) break;
        line = state.doc.line(line.number + 1);
      }
    }
    return Decoration.set(ranges, true);
  },
);

/**
 * Keeps CodeMirror's real selection authoritative while giving Live Preview
 * one stable selection snapshot for syntax projection. Pointer drags update
 * the real selection normally, but projection changes only after mouse-up;
 * a triple click commits immediately because it is one discrete paragraph
 * selection rather than a geometry-dependent drag.
 */
export function createLiveSelectionController(options: {
  handleModifiedLink(view: EditorView, event: MouseEvent): boolean;
  handleProjectedPointerStart(view: EditorView, event: MouseEvent): boolean;
}): LiveSelectionController {
  const beginPointerSelection = StateEffect.define<PointerProjectionPhase>();
  const commitPointerSelection = StateEffect.define<null>();

  const field = StateField.define<LiveProjectionSelectionState>({
    create(state) {
      return {selection: state.selection, pointerPhase: "idle"};
    },
    update(previous, transaction) {
      let selection = previous.selection.map(transaction.changes);
      let pointerPhase = previous.pointerPhase;

      for (const effect of transaction.effects) {
        if (effect.is(beginPointerSelection)) pointerPhase = effect.value;
      }

      if (transaction.docChanged) {
        // Input, composition, and commands must always project the actual
        // post-change selection. A pointer gesture cannot remain pending
        // across a source mutation.
        selection = transaction.state.selection;
        pointerPhase = "idle";
      } else if (transaction.selection
          && (pointerPhase !== "deferred" || !transaction.isUserEvent("select.pointer"))) {
        selection = transaction.state.selection;
      }

      for (const effect of transaction.effects) {
        if (effect.is(commitPointerSelection)) {
          selection = transaction.state.selection;
          pointerPhase = "idle";
        }
      }

      if (selection.eq(previous.selection) && pointerPhase === previous.pointerPhase) {
        return previous;
      }
      return {selection, pointerPhase};
    },
  });

  const pointer = ViewPlugin.fromClass(class {
    private gestureActive = false;
    private destroyed = false;

    constructor(readonly view: EditorView) {}

    private readonly finish = () => {
      if (!this.gestureActive) return;
      this.removeWindowListeners();
      // CodeMirror's own window mouse-up handler publishes the final
      // `select.pointer` transaction in the same event turn. A microtask runs
      // after every listener for that event, so this commit observes the
      // final native selection without timers or a parallel drag tracker.
      queueMicrotask(() => {
        if (this.destroyed || !this.gestureActive) return;
        this.gestureActive = false;
        this.view.dispatch({effects: commitPointerSelection.of(null)});
      });
    };

    private addWindowListeners() {
      window.addEventListener("mouseup", this.finish, true);
      window.addEventListener("blur", this.finish, true);
    }

    private removeWindowListeners() {
      window.removeEventListener("mouseup", this.finish, true);
      window.removeEventListener("blur", this.finish, true);
    }

    mousedown(event: MouseEvent) {
      if (event.button !== 0 || this.view.composing) return false;
      if (options.handleModifiedLink(this.view, event)) return true;

      // A semantic block widget maps one discrete press directly to an exact
      // source position. Commit that selection while the projection phase is
      // still idle so the widget and its boundary cursor cannot coexist for
      // one frame before mouse-up. Ordinary source dragging still defers
      // projection until its gesture completes below.
      if (options.handleProjectedPointerStart(this.view, event)) return true;

      this.removeWindowListeners();
      this.gestureActive = true;
      this.addWindowListeners();
      this.view.dispatch({
        effects: beginPointerSelection.of(event.detail >= 3 ? "immediate" : "deferred"),
      });
      return false;
    }

    destroy() {
      this.destroyed = true;
      this.gestureActive = false;
      this.removeWindowListeners();
    }
  }, {
    eventHandlers: {
      mousedown(event) {
        return this.mousedown(event);
      },
    },
  });

  const selection = (state: EditorState) => state.field(field, false)?.selection ?? state.selection;
  const interaction = (state: EditorState) => state.field(field, false)
    ?? {selection: state.selection, pointerPhase: "idle" as const};
  return {
    extension: [field, pointer],
    selection,
    changed(startState, state) {
      return !selection(startState).eq(selection(state));
    },
    interactionChanged(startState, state) {
      const start = interaction(startState);
      const current = interaction(state);
      return start.pointerPhase !== current.pointerPhase
        || !start.selection.eq(current.selection);
    },
    pointerSelectionIsComplete(state) {
      return interaction(state).pointerPhase === "idle";
    },
  };
}

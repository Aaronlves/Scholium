import {StateEffect, StateField} from "@codemirror/state";
import {Decoration, EditorView, ViewPlugin} from "@codemirror/view";
import {arrivalClass, arrivalDuration} from "./arrival-highlight";

export const showEditorArrival = StateEffect.define<number | null>();
export const editorArrivalState = StateField.define({
  create: () => Decoration.none,
  update(value, transaction) {
    // Edited/replaced source must not leave a marker on a different passage.
    if (transaction.docChanged || transaction.reconfigured) value = Decoration.none;
    for (const effect of transaction.effects) {
      if (!effect.is(showEditorArrival)) continue;
      const position = effect.value;
      value = position !== null && position >= 0 && position <= transaction.newDoc.length
        ? Decoration.set([Decoration.line({class: arrivalClass}).range(transaction.newDoc.lineAt(position).from)])
        : Decoration.none;
    }
    return value;
  },
  provide: field => EditorView.decorations.from(field),
});

const lifetime = ViewPlugin.fromClass(class {
  timer: ReturnType<typeof setTimeout> | undefined;
  constructor(readonly view: EditorView) {}
  update(update: import("@codemirror/view").ViewUpdate) {
    if (update.docChanged || update.transactions.some(transaction => transaction.reconfigured)) {
      clearTimeout(this.timer);
    }
    for (const transaction of update.transactions) for (const effect of transaction.effects) {
      if (!effect.is(showEditorArrival)) continue;
      clearTimeout(this.timer);
      if (effect.value !== null) {
        // CodeMirror may reuse the same line DOM on repeated navigation.
        // Restart only its arrival animation after the decoration is drawn.
        this.view.requestMeasure({
          key: this,
          read: view => view.dom.querySelector('.' + arrivalClass),
          write: marker => {
            for (const animation of marker?.getAnimations() ?? []) {
              if (animation instanceof CSSAnimation && animation.animationName === 'scholium-arrival-fade') {
                animation.currentTime = 0;
                animation.play();
              }
            }
          },
        });
        this.timer = setTimeout(() => {
          this.view.dispatch({effects: showEditorArrival.of(null)});
        }, arrivalDuration);
      }
    }
  }
  destroy() { clearTimeout(this.timer); }
});
export const editorArrivalHighlight = [editorArrivalState, lifetime];

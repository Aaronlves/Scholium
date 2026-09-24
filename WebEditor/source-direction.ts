import type {Extension} from "@codemirror/state";
import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
} from "@codemirror/view";

function directionDecorations(view: EditorView) {
  const ranges = [];
  const decoratedLines = new Set<number>();
  for (const visible of view.visibleRanges) {
    let line = view.state.doc.lineAt(visible.from);
    while (line.from <= visible.to) {
      if (!decoratedLines.has(line.from)) {
        decoratedLines.add(line.from);
        ranges.push(Decoration.line({attributes: {dir: "auto"}}).range(line.from));
      }
      if (line.number >= view.state.doc.lines) break;
      line = view.state.doc.line(line.number + 1);
    }
  }
  return Decoration.set(ranges, true);
}

/**
 * Source remains exact Markdown. This viewport-bounded adapter contributes
 * only the HTML direction attribute consumed by CodeMirror's bidi cursor
 * model; it owns no semantic typography, replacement, or vertical geometry.
 */
export const sourceTextDirection: Extension = ViewPlugin.fromClass(class {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = directionDecorations(view);
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = directionDecorations(update.view);
    }
  }
}, {
  decorations: (value) => value.decorations,
});

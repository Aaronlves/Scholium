import {EditorSelection, EditorState} from "@codemirror/state";
import {EditorView} from "@codemirror/view";

/** Apply CodeMirror's macOS pointer modifier policy to an exact projected target. */
export function projectedPointerSelection(
  state: EditorState,
  event: MouseEvent,
  sourceOffset: number,
  assoc = 0,
): EditorSelection {
  const head = Math.max(0, Math.min(sourceOffset, state.doc.length));
  const range = EditorSelection.cursor(head, assoc);
  const selection = state.selection;
  if (event.shiftKey) {
    return selection.replaceRange(selection.main.extend(range.from, range.to, range.assoc));
  }
  const modifiers = state.facet(EditorView.clickAddsSelectionRange);
  const multiple = state.facet(EditorState.allowMultipleSelections)
    && (modifiers.length ? modifiers[0](event) : event.metaKey);
  if (!multiple) return EditorSelection.create([range]);

  // Stock mouse selection toggles a containing range on a single modified
  // click, but never removes the editor's only remaining range.
  if (event.detail === 1 && selection.ranges.length > 1) {
    const index = selection.ranges.findIndex(candidate => candidate.from <= head && candidate.to >= head);
    if (index >= 0) {
      const ranges = selection.ranges.slice(0, index).concat(selection.ranges.slice(index + 1));
      const main = selection.mainIndex === index ? 0
        : selection.mainIndex - (selection.mainIndex > index ? 1 : 0);
      return EditorSelection.create(ranges, main);
    }
  }
  return selection.addRange(range);
}

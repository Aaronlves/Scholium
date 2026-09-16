import {EditorState, StateEffect, StateField, type Extension} from "@codemirror/state";
import {EditorView} from "@codemirror/view";

/** A capture lease freezes its exact editor state until the matching resume. */
export const setEditorSuspension = StateEffect.define<string | null>();
export const editorSuspensionState = StateField.define<string | null>({
  create: () => null,
  update(value, transaction) {
    if (value !== null && transaction.docChanged) throw new Error("editor is suspended for detachment");
    const change = transaction.effects.find(effect => effect.is(setEditorSuspension));
    return change ? change.value : value;
  },
});
export const editorSuspension: Extension = [
  editorSuspensionState,
  EditorState.readOnly.from(editorSuspensionState, token => token !== null),
  EditorView.editable.from(editorSuspensionState, token => token === null),
  EditorView.editorAttributes.from(editorSuspensionState, (token): Record<string, string> => token === null ? {} : {inert: ""}),
  EditorState.transactionFilter.of(transaction =>
    transaction.startState.field(editorSuspensionState) !== null && transaction.docChanged ? [] : transaction),
];

/** A filename draft belongs to its live control and is not in source recovery. */
export function titleAllowsDetachment(title: string, draft: string | null, renamePending: boolean) {
  return !renamePending && (draft === null || draft === title);
}

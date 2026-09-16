import {EditorState, Transaction, type Extension} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {setExactSource} from "./exact-source-history";
import {normalizedDocumentText} from "./state";

/** A reused runtime must not transfer document-owned fields or history. */
export function createMarkdownDocumentState(source: string, extensions: Extension[]) {
  return EditorState.create({doc: normalizedDocumentText(source), extensions})
    .update({effects: setExactSource.of(source),
      annotations: Transaction.addToHistory.of(false)}).state;
}

export function createMarkdownEditor(parent: HTMLElement, extensions: Extension[]) {
  return new EditorView({parent, state: EditorState.create({doc: "", extensions})});
}

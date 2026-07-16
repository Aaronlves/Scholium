import {EditorState, type Extension} from "@codemirror/state";
import {EditorView} from "@codemirror/view";

export function createMarkdownEditor(parent: HTMLElement, extensions: Extension[]) {
  return new EditorView({parent, state: EditorState.create({doc: "", extensions})});
}

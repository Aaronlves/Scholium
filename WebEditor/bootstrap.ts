import {EditorState, type Extension, type EditorSelection} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {exactSourceFits, sourceCapacityMessage, exactSourceState} from "./exact-source-history";
import {ExactSourceMirror, normalizedDocumentText} from "./state";
import {citationState, type ZoteroCitationSnapshot} from "./zotero-citation-state";
import {recordEditorMetric} from "./performance";

/** A reused runtime must not transfer document-owned fields or history. */
export function createMarkdownDocumentState(source: string, extensions: Extension[], initial?: {
  selection?: EditorSelection;
  citationSnapshot?: ZoteroCitationSnapshot;
}) {
  if (!exactSourceFits(source)) throw new Error(sourceCapacityMessage);
  const snapshot = initial?.citationSnapshot;
  return EditorState.create({
    doc: normalizedDocumentText(source), selection: initial?.selection,
    extensions: [extensions, exactSourceState.init(() => new ExactSourceMirror(source)),
      citationState.init(() => snapshot ? {baseline: snapshot, data: snapshot.data} : undefined)],
  });
}

export function createMarkdownEditor(parent: HTMLElement, extensions: Extension[]) {
  const stateStartedAt = performance.now();
  const state = EditorState.create({doc: "", extensions});
  recordEditorMetric("bootstrap-state", stateStartedAt);
  const viewStartedAt = performance.now();
  const view = new EditorView({parent, state});
  recordEditorMetric("bootstrap-view", viewStartedAt);
  return view;
}

/** Completes CodeMirror's real measure even when WebKit animation frames pause. */
export function measureMarkdownEditor(view: EditorView, read: () => void): Promise<void> {
  return new Promise((resolve, reject) => {
    try {
      view.requestMeasure({
        read: () => {
          try { read(); return true; }
          catch (error) {
            // CodeMirror drops write after a throwing read. Reject inside the
            // callback so a real error cannot leave readiness pending forever.
            reject(error);
            return false;
          }
        },
        write: measured => { if (measured) resolve(); },
      });
      // This public geometry API flushes the queued read/write measurement
      // synchronously outside an editor update, as in source-range revelation.
      view.coordsAtPos(view.state.selection.main.head);
    } catch (error) { reject(error); }
  });
}

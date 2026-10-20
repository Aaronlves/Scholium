import {EditorSelection, EditorState, Transaction, type Extension} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {exactSourceFits, sourceCapacityMessage, exactSourceState, restoreExactHistory} from "./exact-source-history";
import {ExactSourceMirror, normalizedDocumentText} from "./state";
import {citationDataEqual, citationSnapshotEqual, citationState, setCitationData, setCitationSnapshot, type ZoteroCitationData, type ZoteroCitationSnapshot} from "./zotero-citation-state";
import {recordEditorMetric} from "./performance";
import type {RecoverySnapshot} from "./protocol";

/** A reused runtime must not transfer document-owned fields or history. */
export function createMarkdownDocumentState(source: string, extensions: Extension[], initial?: {
  selection?: EditorSelection;
  citationSnapshot?: ZoteroCitationSnapshot;
  citationData?: ZoteroCitationData;
}) {
  if (!exactSourceFits(source)) throw new Error(sourceCapacityMessage);
  const snapshot = initial?.citationSnapshot;
  return EditorState.create({
    doc: normalizedDocumentText(source), selection: initial?.selection,
    extensions: [extensions, exactSourceState.init(() => new ExactSourceMirror(source)),
      citationState.init(() => snapshot ? {baseline: snapshot,
        data: initial && "citationData" in initial ? initial.citationData : snapshot.data} : undefined)],
  });
}

/** Build the complete recovered state before the live view installs it. */
export function restoreMarkdownDocumentState(snapshot: RecoverySnapshot, extensions: Extension[]) {
  const startedAt = performance.now();
  const observed: Record<string, number> = {rangeCount: snapshot.ranges.length, historyPreserved: 0, completed: 0};
  try {
    const selection = EditorSelection.create(snapshot.ranges.map(range => EditorSelection.range(range.anchor, range.head)));
    observed.selectionMilliseconds = performance.now() - startedAt;
    if (snapshot.stateJSON) {
      const historyStartedAt = performance.now();
      try {
        const restored = restoreExactHistory(snapshot.stateJSON, snapshot.source, extensions);
        observed.codecMilliseconds = performance.now() - historyStartedAt;
        const bindingStartedAt = performance.now();
        const citations = restored.field(citationState);
        if (!citationDataEqual(citations?.data, snapshot.citationData)
            || citations?.baseline.noteID !== snapshot.citationSnapshot?.noteID
            || citations?.baseline.vaultID !== snapshot.citationSnapshot?.vaultID) {
          throw new Error("Citation history mismatch");
        }
        // A detached save can advance the disk baseline without changing the
        // draft's semantic data or Undo. Rebase only that nonhistory boundary.
        const rebase = snapshot.citationSnapshot
          && !citationSnapshotEqual(citations?.baseline, snapshot.citationSnapshot);
        const state = restored.update({selection,
          effects: rebase
            ? [setCitationSnapshot.of(snapshot.citationSnapshot), setCitationData.of(citations?.data)] : [],
          annotations: Transaction.addToHistory.of(false),
        }).state;
        observed.bindingMilliseconds = performance.now() - bindingStartedAt;
        observed.historyPreserved = 1;
        observed.completed = 1;
        return {state, historyPreserved: true};
      } catch {
        observed.failedHistoryAttemptMilliseconds = performance.now() - historyStartedAt;
        // Exact source remains recoverable when the history codec refuses it.
      }
    }
    const fallbackStartedAt = performance.now();
    const state = createMarkdownDocumentState(snapshot.source, extensions, {
      selection, citationSnapshot: snapshot.citationSnapshot, citationData: snapshot.citationData,
    });
    observed.fallbackMilliseconds = performance.now() - fallbackStartedAt;
    observed.completed = 1;
    return {state, historyPreserved: false};
  } finally {
    recordEditorMetric("recovery-composition", startedAt, observed);
  }
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

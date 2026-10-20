import {EditorSelection, EditorState, Facet, StateField} from "@codemirror/state";
import {history, isolateHistory, redo, redoDepth, undo, undoDepth} from "@codemirror/commands";
import {codeFolding, foldEffect, foldedRanges} from "@codemirror/language";
import {getSearchQuery, SearchQuery, setSearchQuery} from "@codemirror/search";
import {describe, expect, it} from "vitest";
import {createMarkdownDocumentState, restoreMarkdownDocumentState} from "../bootstrap";
import {documentFindExtension} from "../document-find";
import {captureExactHistory, exactSourceHistory, exactSourceState} from "../exact-source-history";
import {citationHistory, citationState, setCitationData, type ZoteroCitationSnapshot} from "../zotero-citation-state";
import {normalizedDocumentText} from "../state";
import type {RecoverySnapshot} from "../protocol";

const extensions = [history(), exactSourceHistory, citationHistory, documentFindExtension, codeFolding(),
  EditorState.lineSeparator.of("\n")];
const incomingMode = Facet.define<string, string>({combine: values => values[0] ?? "source"});
const exact = (state: EditorState) => state.field(exactSourceState).text;
function step(state: EditorState, command: typeof undo) {
  let next = state;
  expect(command({state, dispatch: transaction => { next = transaction.state; }})).toBe(true);
  return next;
}
function recoverySnapshot(state: EditorState): RecoverySnapshot {
  return {documentID: "document", fingerprint: "baseline", generation: 7, source: exact(state),
    ranges: state.selection.ranges.map(range => ({anchor: range.anchor, head: range.head})),
    stateJSON: captureExactHistory(state), undoHistoryPreserved: true, hasHistory: true, dirty: true,
    citationSnapshot: state.field(citationState)?.baseline, citationData: state.field(citationState)?.data};
}

describe("document initialization in a retained editor runtime", () => {
  it("creates exact source, target selection and citations before derived fields initialize", () => {
    const source = "\uFEFF---\r\ntags: [draft]\r\n---\r\nBody 中文😀\r\n";
    const head = normalizedDocumentText(source).indexOf("Body");
    const snapshot = {noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222", status: "absent" as const};
    const observations: unknown[] = [];
    const observer = StateField.define({create: state => {
      observations.push([state.selection.main.head, state.field(exactSourceState).text, state.field(citationState)?.baseline]);
      return null;
    }, update: value => value});
    const state = createMarkdownDocumentState(source, [observer, ...extensions], {
      selection: EditorSelection.single(head), citationSnapshot: snapshot,
    });
    expect(observations).toEqual([[head, source, snapshot]]);
    expect(state.selection.main.head).toBe(head);
    expect(undoDepth(state)).toBe(0);
  });

  it("starts the next document with clean history, find, folding and selection", () => {
    let first = createMarkdownDocumentState("first\r\nsecret\r\n", extensions);
    first = first.update({changes: {from: 5, insert: " edited"},
      selection: {anchor: 3, head: 12}, effects: [
        setSearchQuery.of(new SearchQuery({search: "secret", replace: "hidden"})),
        foldEffect.of({from: 12, to: 19}),
      ]}).state;
    expect(undoDepth(first)).toBe(1);
    expect(foldedRanges(first).size).toBe(1);
    expect(getSearchQuery(first).search).toBe("secret");

    const second = createMarkdownDocumentState("\uFEFFsecond\r\n界😀é\n", extensions);
    expect(second.field(exactSourceState).text).toBe("\uFEFFsecond\r\n界😀é\n");
    expect(second.doc.toString()).toBe(normalizedDocumentText("\uFEFFsecond\r\n界😀é\n"));
    expect(second.selection.main.anchor).toBe(0);
    expect(second.selection.main.head).toBe(0);
    expect(undoDepth(second)).toBe(0);
    expect(redoDepth(second)).toBe(0);
    expect(foldedRanges(second).size).toBe(0);
    expect(getSearchQuery(second).search).toBe("");
    expect(undo({state: second, dispatch: () => { throw new Error("old document Undo escaped"); }}))
      .toBe(false);
  });

  it("keeps exact first-edit Undo local and supports explicit previous-document recovery", () => {
    const source = "\uFEFFA\r\nB\nC\r\n";
    let first = createMarkdownDocumentState(source, extensions);
    first = first.update({changes: {from: 2, to: 3}, selection: {anchor: 3}}).state;
    const recovery = captureExactHistory(first)!;
    const secondSource = "other\r\n";
    let second = createMarkdownDocumentState(secondSource, extensions);
    second = second.update({changes: {from: 0, insert: "new "}}).state;
    expect(undo({state: second, dispatch: transaction => { second = transaction.state; }})).toBe(true);
    expect(second.field(exactSourceState).text).toBe(secondSource);
    expect(undoDepth(second)).toBe(0);

    const initialized = restoreMarkdownDocumentState({...recoverySnapshot(first), stateJSON: recovery}, extensions);
    expect(initialized.historyPreserved).toBe(true);
    let restored = initialized.state;
    expect(restored.selection.eq(first.selection)).toBe(true);
    expect(undo({state: restored, dispatch: transaction => { restored = transaction.state; }})).toBe(true);
    expect(restored.field(exactSourceState).text).toBe(source);
  });

  it.each(["livePreview", "source"])("restores complete selection and both history branches under incoming %s configuration", mode => {
    const source = "\uFEFFA\r\nCafe\u0301 中文 🦉\nTail\rEnd";
    let state = createMarkdownDocumentState(source, extensions);
    state = state.update({changes: {from: state.doc.length, insert: " first"},
      annotations: isolateHistory.of("full")}).state;
    state = state.update({changes: {from: 1, insert: "second "},
      annotations: isolateHistory.of("full")}).state;
    state = step(state, undo);
    const snapshot = recoverySnapshot(state);
    expect(snapshot.stateJSON).toBeDefined();
    snapshot.ranges = [{anchor: 1, head: 3}, {anchor: state.doc.length - 2, head: state.doc.length}];
    const restored = restoreMarkdownDocumentState(snapshot, [
      ...extensions, EditorState.allowMultipleSelections.of(true), incomingMode.of(mode),
    ]);
    expect(restored.historyPreserved).toBe(true);
    expect(exact(restored.state)).toBe(snapshot.source);
    expect(restored.state.selection.ranges.map(range => ({anchor: range.anchor, head: range.head}))).toEqual(snapshot.ranges);
    expect(restored.state.facet(incomingMode)).toBe(mode);
    expect(undoDepth(restored.state)).toBe(undoDepth(state));
    expect(redoDepth(restored.state)).toBe(redoDepth(state));
    expect(exact(step(restored.state, undo))).toBe(source);
    expect(exact(step(restored.state, redo))).toBe(exact(step(state, redo)));
  });

  it("rebases a saved citation baseline while retaining draft citation Undo", () => {
    const source = "\uFEFFDraft e\u0301\r\n";
    const initialData = {schemaVersion: 1 as const, fields: [], documentData: "initial companion"};
    const draftData = {...initialData, documentData: "draft companion"};
    const baseline: ZoteroCitationSnapshot = {
      noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222",
      status: "available", sourceFingerprint: {sha256: "a".repeat(64), byteCount: 4}, data: initialData,
    };
    const state = createMarkdownDocumentState(source, extensions, {citationSnapshot: baseline}).update({
      effects: setCitationData.of(draftData), annotations: isolateHistory.of("full"),
    }).state;
    const snapshot = recoverySnapshot(state);
    expect(snapshot.stateJSON).toBeDefined();
    snapshot.citationSnapshot = {...baseline, revision: {sha256: "b".repeat(64), byteCount: 42}, data: draftData};
    const restored = restoreMarkdownDocumentState(snapshot, extensions);
    expect(restored.historyPreserved).toBe(true);
    expect(exact(restored.state)).toBe(source);
    expect(restored.state.field(citationState)).toEqual({baseline: snapshot.citationSnapshot, data: draftData});
    const undone = step(restored.state, undo);
    expect(exact(undone)).toBe(source);
    expect(undone.field(citationState)).toEqual({baseline: snapshot.citationSnapshot, data: initialData});
    expect(step(undone, redo).field(citationState)?.data).toEqual(draftData);
  });

  it.each(["missing", "malformed", "foreign-source", "citation-mismatch"])(
    "recovers exact source and draft metadata with no history after %s history", kind => {
      const source = "\uFEFFDraft\r\nCafe\u0301 🦉\nTail\rEnd";
      const baseline: ZoteroCitationSnapshot = {
        noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222",
        status: "available", sourceFingerprint: {sha256: "a".repeat(64), byteCount: 4},
        data: {schemaVersion: 1, fields: [], documentData: "committed"},
      };
      const state = createMarkdownDocumentState(source, extensions, {citationSnapshot: baseline}).update({
        changes: {from: 1, insert: "edited "},
      }).state;
      const snapshot = recoverySnapshot(state);
      expect(snapshot.stateJSON).toBeDefined();
      snapshot.ranges = [{anchor: 1, head: 5}, {anchor: 10, head: 12}];
      snapshot.citationData = {...baseline.data!, documentData: "pending companion"};
      if (kind === "missing") snapshot.stateJSON = undefined;
      if (kind === "malformed") snapshot.stateJSON = "{";
      if (kind === "foreign-source") {
        snapshot.stateJSON = captureExactHistory(createMarkdownDocumentState("another document", extensions));
      }
      const restored = restoreMarkdownDocumentState(snapshot, [
        ...extensions, EditorState.allowMultipleSelections.of(true), incomingMode.of("livePreview"),
      ]);
      expect(restored.historyPreserved).toBe(false);
      expect(exact(restored.state)).toBe(snapshot.source);
      expect(restored.state.selection.ranges.map(range => ({anchor: range.anchor, head: range.head}))).toEqual(snapshot.ranges);
      expect(restored.state.field(citationState)).toEqual({baseline, data: snapshot.citationData});
      expect(restored.state.facet(incomingMode)).toBe("livePreview");
      expect(undoDepth(restored.state)).toBe(0);
      expect(redoDepth(restored.state)).toBe(0);
      expect(exact(state)).toBe(snapshot.source);
    });

  it("does not replace explicitly absent draft companion data with the saved baseline", () => {
    const baseline: ZoteroCitationSnapshot = {
      noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222",
      status: "available", sourceFingerprint: {sha256: "a".repeat(64), byteCount: 4},
      data: {schemaVersion: 1, fields: []},
    };
    const snapshot = recoverySnapshot(createMarkdownDocumentState("Body", extensions, {citationSnapshot: baseline}));
    snapshot.stateJSON = undefined;
    snapshot.citationData = undefined;
    const restored = restoreMarkdownDocumentState(snapshot, extensions);
    expect(restored.historyPreserved).toBe(false);
    expect(restored.state.field(citationState)).toEqual({baseline, data: undefined});
  });
});

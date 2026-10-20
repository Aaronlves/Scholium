import {EditorSelection, EditorState, StateField, Transaction} from "@codemirror/state";
import {history, historyField, isolateHistory, redo, redoDepth, redoSelection, undo, undoDepth, undoSelection} from "@codemirror/commands";
import {DOMParser} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {createMarkdownDocumentState, restoreMarkdownDocumentState} from "../bootstrap";
import {captureExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory, setExactSource} from "../exact-source-history";
import {scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {citationHistory, citationState, setCitationData, type ZoteroCitationSnapshot} from "../zotero-citation-state";
import {normalizedDocumentText} from "../state";

vi.stubGlobal("DOMParser", DOMParser);
const extensions = [history(), exactSourceHistory, citationHistory, scholiumNoteLanguage,
  EditorState.allowMultipleSelections.of(true), EditorState.lineSeparator.of("\n")];
const source = "\uFEFF# Cafe\u0301\r\n\r\nClaim 中文 🦉 [Author](cite:cite_a).\nTail\rEnd\r\nLast";
const citationSnapshot: ZoteroCitationSnapshot = {
  noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222",
  status: "available", sourceFingerprint: {sha256: "a".repeat(64), byteCount: new TextEncoder().encode(source).byteLength},
  data: {schemaVersion: 1, fields: [{id: "cite_a", kind: "citation", code: "ITEM CSL_CITATION synthetic", text: "Author"}],
    acceptedFields: [{id: "cite_a", code: "ITEM CSL_CITATION synthetic"}]},
};
const exact = (state: EditorState) => state.field(exactSourceState).text;
type Controller = ReturnType<typeof createLiveProjectionIndexController>;

function step(state: EditorState, command: typeof undo) {
  let next = state;
  expect(command({state, dispatch: transaction => { next = transaction.state; }})).toBe(true);
  return next;
}

function expectFreshIndex(state: EditorState, controller: Controller) {
  const oracle = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
  const citations = state.field(citationState);
  const fresh = createMarkdownDocumentState(exact(state), [...extensions, oracle.extension], {
    selection: state.selection, citationSnapshot: citations?.baseline, citationData: citations?.data,
  });
  expect(controller.index(state).syntaxComplete).toBe(true);
  expect(controller.index(state)).toEqual(oracle.index(fresh));
}

describe("semantic projection during exact history recovery", () => {
  it("initializes the real index once against exact source and preserves both history and selection branches", () => {
    let builds = 0;
    const controller = createLiveProjectionIndexController({editingDialect: () => null,
      recordMetric: (name, _startedAt, observed) => {
        if (name === "projection-index" && (observed?.documentLength ?? 0) > 0) builds++;
      }});
    const observedExactSources: string[] = [];
    const observer = StateField.define({
      create: state => { observedExactSources.push(exact(state)); return null; }, update: value => value,
    });
    const incomingExtensions = [...extensions, observer, controller.extension];
    let original = createMarkdownDocumentState(source, incomingExtensions, {citationSnapshot});
    const newline = original.doc.toString().indexOf("\n");
    original = original.update({changes: {from: newline, to: newline + 1},
      annotations: [isolateHistory.of("full"), Transaction.time.of(1_000)]}).state;
    original = original.update({changes: {from: original.doc.length, insert: " Ω\n"},
      annotations: [isolateHistory.of("full"), Transaction.time.of(2_000)]}).state;
    original = step(original, undo);
    const claim = original.doc.toString().indexOf("Claim");
    original = original.update({selection: EditorSelection.create([
      EditorSelection.range(claim, claim + 5), EditorSelection.cursor(original.doc.length),
    ], 1), userEvent: "select.pointer", annotations: Transaction.time.of(3_000)}).state;
    expect(undoDepth(original)).toBe(1);
    expect(redoDepth(original)).toBe(1);
    const serialized = captureExactHistory(original);
    expect(serialized).toBeDefined();
    builds = 0;
    observedExactSources.length = 0;

    // No saved companion rebase occurs in this codec boundary. The actual
    // language/index fields must see the final mirror on their first creation.
    const restored = restoreExactHistory(serialized!, exact(original), incomingExtensions);
    expect(builds).toBe(1);
    expect(observedExactSources).toEqual([exact(original)]);
    expect(restored.selection.ranges).toHaveLength(2);
    expect(restored.selection.mainIndex).toBe(1);
    expect(restored.toJSON({history: historyField, citations: citationState}))
      .toEqual(original.toJSON({history: historyField, citations: citationState}));
    expectFreshIndex(restored, controller);
    expect(controller.index(restored).zoteroFields.fields.map(field => field.id)).toEqual(["cite_a"]);

    for (const command of [undo, redo, undoSelection, redoSelection]) {
      let before = original, after = restored;
      while (command({state: before, dispatch: transaction => { before = transaction.state; }})) {
        after = step(after, command);
        expect(exact(after)).toBe(exact(before));
        expect(after.selection.eq(before.selection)).toBe(true);
        expect(after.field(citationState)).toEqual(before.field(citationState));
        expectFreshIndex(after, controller);
      }
      expect(command({state: after, dispatch: () => {}})).toBe(false);
    }
    expect(exact(step(restored, undo))).toBe(source);
  });

  it("rebuilds exact citation projection when only CRLF bytes change", () => {
    let builds = 0;
    const controller = createLiveProjectionIndexController({editingDialect: () => null,
      recordMetric: name => { if (name === "projection-index") builds++; }});
    const original = createMarkdownDocumentState(source, [...extensions, controller.extension], {citationSnapshot});
    const originalIndex = controller.index(original);
    const replacement = source.replaceAll("\r\n", "\n");
    expect(normalizedDocumentText(replacement)).toBe(original.doc.toString());
    const before = builds;
    const changed = original.update({effects: setExactSource.of(replacement),
      annotations: Transaction.addToHistory.of(false)}).state;

    expect(changed.doc.toString()).toBe(original.doc.toString());
    expect(exact(changed)).toBe(replacement);
    expect(builds).toBe(before + 1);
    expect(controller.index(changed)).not.toBe(originalIndex);
    expect(originalIndex.zoteroFields.source).toBe(source);
    expect(controller.index(changed).zoteroFields.source).toBe(replacement);
    expect(controller.index(changed).zoteroFields.fields[0].range.from)
      .toBeLessThan(originalIndex.zoteroFields.fields[0].range.from);
    expectFreshIndex(changed, controller);
    expect(undoDepth(changed)).toBe(0);
  });

  it("skips an equal citation baseline but reprojects a saved revision without losing draft Undo", () => {
    let builds = 0;
    const controller = createLiveProjectionIndexController({editingDialect: () => null,
      recordMetric: name => { if (name === "projection-index") builds++; }});
    const incomingExtensions = [...extensions, controller.extension];
    const draftData = {...citationSnapshot.data!, documentData: "draft companion"};
    const original = createMarkdownDocumentState(source, incomingExtensions, {citationSnapshot}).update({
      effects: setCitationData.of(draftData), annotations: isolateHistory.of("full"),
    }).state;
    const snapshot = {documentID: "synthetic", fingerprint: "a".repeat(64), generation: 1,
      source, ranges: original.selection.ranges.map(({anchor, head}) => ({anchor, head})),
      stateJSON: captureExactHistory(original), undoHistoryPreserved: true, hasHistory: true, dirty: true,
      citationSnapshot, citationData: draftData};
    expect(snapshot.stateJSON).toBeDefined();
    builds = 0;
    const unchanged = restoreMarkdownDocumentState(snapshot, incomingExtensions);
    expect(unchanged.historyPreserved).toBe(true);
    expect(builds).toBe(1);
    expect(unchanged.state.field(citationState)).toEqual({baseline: citationSnapshot, data: draftData});
    expectFreshIndex(unchanged.state, controller);

    const savedBaseline: ZoteroCitationSnapshot = {...citationSnapshot,
      revision: {sha256: "b".repeat(64), byteCount: 42}, data: draftData};
    builds = 0;
    const rebased = restoreMarkdownDocumentState({...snapshot, citationSnapshot: savedBaseline}, incomingExtensions);
    expect(rebased.historyPreserved).toBe(true);
    expect(builds).toBe(2);
    expect(rebased.state.field(citationState)).toEqual({baseline: savedBaseline, data: draftData});
    expectFreshIndex(rebased.state, controller);
    const undone = step(rebased.state, undo);
    expect(exact(undone)).toBe(source);
    expect(undone.field(citationState)).toEqual({baseline: savedBaseline, data: citationSnapshot.data});
    expectFreshIndex(undone, controller);
    const redone = step(undone, redo);
    expect(exact(redone)).toBe(source);
    expect(redone.field(citationState)).toEqual({baseline: savedBaseline, data: draftData});
    expectFreshIndex(redone, controller);
  });
});

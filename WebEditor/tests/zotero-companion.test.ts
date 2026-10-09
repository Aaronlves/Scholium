import {EditorState, Transaction} from "@codemirror/state";
import {history, redo, undo, undoDepth} from "@codemirror/commands";
import {DOMParser} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {captureExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory, setExactSource} from "../exact-source-history";
import {citationHistory, citationState, setCitationSnapshot, setCitationData, validCitationData, type ZoteroCitationData, type ZoteroCitationSnapshot} from "../zotero-citation-state";
import {convertEmbeddedFields, encodeDocumentData, encodeField, fieldOperationTransaction, projectFields, projectFieldsForState, stageFieldOperation} from "../zotero-fields";
import {normalizedDocumentText} from "../state";
import {ZoteroMarkdownTransaction, type ZoteroTransactionCapture} from "../zotero-transaction";
import {linkTargetAt} from "../link-target";
import {appendMarkdownBlocks} from "../markdown-fragment";

vi.stubGlobal("DOMParser", DOMParser);
const code = (id: number) => `ITEM CSL_CITATION {"citationID":"vendor-${id}","citationItems":[{"id":${id}}],"properties":{"plainCitation":"(同文, 2026)"}}`;
const data: ZoteroCitationData = {schemaVersion: 1, fields: [{id: "cfirst", kind: "citation", code: code(1), text: "(同文, 2026)"}],
  documentData: '<data style="author-date"/>', acceptedFields: [{id: "cfirst", code: code(1)}]};
const source = "\uFEFF---\r\nunknown: 'keep' # authored\n---\r\nArgument 😀 e\u0301 [\\(同文, 2026\\)](cite:cfirst)\r\nUnchanged tail";
const snapshot = (value: ZoteroCitationData | undefined = data): ZoteroCitationSnapshot => ({
  noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222",
  sourceFingerprint: {sha256: "a".repeat(64), byteCount: new TextEncoder().encode(source).byteLength},
  ...(value ? {data: value, status: "available" as const} : {status: "absent" as const}),
});
const extensions = [history(), exactSourceHistory, citationHistory, EditorState.lineSeparator.of("\n")];
function initial(text = source, value: ZoteroCitationSnapshot = snapshot()) {
  return EditorState.create({doc: normalizedDocumentText(text), extensions})
    .update({effects: [setExactSource.of(text), setCitationSnapshot.of(value)], annotations: Transaction.addToHistory.of(false)}).state;
}
function perform(state: EditorState, command: typeof undo) {
  let next = state;
  expect(command({state, dispatch: transaction => { next = transaction.state; }})).toBe(true);
  return next;
}
function commit(state: EditorState, operation: ReturnType<typeof stageFieldOperation>) {
  const spec = fieldOperationTransaction(state, operation);
  expect(spec).not.toBeNull();
  return state.update(spec!).state;
}
const context: ZoteroTransactionCapture = {transactionID: "transaction-1", command: "refresh", mode: "livePreview",
  interactionRevision: 0, compositionRevision: 0, composing: false};
const complete = {status: "cleanedUp", remoteCleanupConfirmed: true} as const;

describe("managed Zotero citation companions", () => {
  it("inserts, edits and refreshes compact citations through the existing Zotero callbacks", () => {
    const emptySource = "\uFEFFOpening 😀\r\n";
    const absent: ZoteroCitationSnapshot = {noteID: snapshot().noteID, vaultID: snapshot().vaultID, status: "absent"};
    const before = initial(emptySource, absent).update({selection: {anchor: normalizedDocumentText(emptySource).length}}).state;
    const insertionContext = {...context, command: "addEditCitation" as const};
    const insertion = ZoteroMarkdownTransaction.capture(before, insertionContext);
    insertion.applyCallback(before, insertionContext, {type: "setDocumentData", value: data.documentData!});
    const reply = insertion.applyCallback(before, insertionContext, {type: "insertField"});
    if (reply.kind !== "field" || !reply.value) throw new Error("Missing inserted citation");
    const id = reply.value.id;
    expect(id).toMatch(/^c[0-9a-f]{32}$/);
    insertion.applyCallback(before, insertionContext, {type: "setFieldCode", id, code: code(2)});
    insertion.applyCallback(before, insertionContext, {type: "setFieldText", id, html: "(同文, 2026)"});
    const after = commit(before, insertion.finalize(before, insertionContext, complete)!);
    expect(after.field(exactSourceState).text).toBe(emptySource + `[\\(同文\\, 2026\\)](cite:${id})`);
    expect(after.field(citationState)?.baseline).toEqual(absent);
    expect(undoDepth(after)).toBe(1);
    const field = projectFieldsForState(after).fields[0];
    const editing = after.update({selection: {anchor: normalizedDocumentText(after.field(exactSourceState).text.slice(0, field.fallbackRange.from)).length}}).state;
    const edit = ZoteroMarkdownTransaction.capture(editing, insertionContext);
    edit.applyCallback(editing, insertionContext, {type: "setFieldText", id, html: "Changed"});
    const edited = commit(editing, edit.finalize(editing, insertionContext, complete)!);
    expect(projectFieldsForState(edited).fields[0]).toMatchObject({id, text: "Changed", code: code(2)});
    const refresh = ZoteroMarkdownTransaction.capture(edited, context);
    expect(refresh.applyCallback(edited, context, {type: "getFields"}).kind).toBe("fields");
    expect(refresh.finalize(edited, context, complete)).toBeNull();
    const restarted = initial(edited.field(exactSourceState).text, snapshot(edited.field(citationState)?.data));
    expect(projectFieldsForState(restarted).fields[0]).toMatchObject({id, text: "Changed", code: code(2)});
  });

  it("uses exact occurrence IDs despite repeated identical citation text", () => {
    const text = source + " [\\(同文, 2026\\)](cite:csecond)";
    const metadata: ZoteroCitationData = {...data, fields: [...data.fields, {...data.fields[0], id: "csecond", code: code(2)}]};
    const projection = projectFields(text, metadata);
    expect(projection.diagnostics).toEqual([]);
    expect(projection.fields.map(({id, code}) => [id, code])).toEqual([["cfirst", code(1)], ["csecond", code(2)]]);
    expect(projection.fields[0].text).toBe(projection.fields[1].text);
    expect(projection.citationStateStale).toBe(true);
  });

  it("refuses copied duplicate IDs, unknown companions and unsupported records without guessing from text", () => {
    expect(projectFields(source + " [same](cite:cfirst)", data).diagnostics.map(d => d.kind)).toContain("duplicate-id");
    expect(projectFields(source, null).diagnostics.length).toBeGreaterThan(0);
    expect(projectFields(source.replace("cfirst", "cunknown"), data).diagnostics.length).toBeGreaterThan(0);
    expect(() => ZoteroMarkdownTransaction.capture(initial(source, {...snapshot(), status: "unsupported"}), context)).toThrow(/recovery/);
    expect(() => ZoteroMarkdownTransaction.capture(initial(source, {...snapshot(), status: "unresolved"}), context)).toThrow(/recovery/);
    expect(validCitationData({...data, schemaVersion: 2})).toBe(false);
    expect(validCitationData({...data, fields: [...data.fields, data.fields[0]]})).toBe(false);
    expect(validCitationData({...data, documentData: "x".repeat(256 * 1024 + 1)})).toBe(false);
  });

  it("keeps plain readable labels non-navigable even without a companion", () => {
    for (const destination of ["cite:cfirst", "CITE:cfirst", "cite:bad/id", "cite:"]) {
      const markdown = `[Readable](${destination})`;
      expect(linkTargetAt(markdown, 3)).toBeNull();
      const dom = new DOMParser().parseFromString("<html><body></body></html>", "text/html");
      appendMarkdownBlocks(markdown, dom.body as unknown as HTMLElement);
      expect(dom.body.querySelector("[data-scholium-link-target]" )).toBeNull();
    }
    const dom = new DOMParser().parseFromString("<html><body></body></html>", "text/html");
    appendMarkdownBlocks("[Readable](cite:cfirst)", dom.body as unknown as HTMLElement);
    expect(dom.body.textContent).toBe("Readable");
  });

  it("accepts metadata-only changes as one Undo, then restores both history branches", () => {
    const before = initial();
    const operation = stageFieldOperation(projectFieldsForState(before), {documentData: '<data style="numeric"/>', acceptCurrentFields: true});
    expect(operation.changes).toEqual([]);
    const after = commit(before, operation);
    expect(after.field(exactSourceState).text).toBe(source);
    expect(after.field(citationState)?.data?.documentData).toBe('<data style="numeric"/>');
    expect(undoDepth(after)).toBe(1);
    const serialized = captureExactHistory(after);
    expect(serialized).toBeDefined();
    const restored = restoreExactHistory(serialized!, source, extensions);
    expect(restored.field(citationState)?.data).toEqual(after.field(citationState)?.data);
    const undone = perform(restored, undo);
    expect(undone.field(citationState)?.data).toEqual(data);
    expect(undone.field(exactSourceState).text).toBe(source);
    const redoRecovery = restoreExactHistory(captureExactHistory(undone)!, source, extensions);
    expect(perform(redoRecovery, redo).field(citationState)?.data).toEqual(after.field(citationState)?.data);
  });

  it("groups source and vendor metadata edits and preserves mixed newline/BOM/Unicode through recovery", () => {
    const before = initial();
    const operation = stageFieldOperation(projectFieldsForState(before), {updates: [{id: "cfirst", text: "<i>Changed</i> 😀", code: code(2)}], acceptCurrentFields: true});
    const after = commit(before, operation);
    expect(after.field(exactSourceState).text).toBe(source.replace("[\\(同文, 2026\\)]", "[*Changed* 😀]"));
    expect(after.field(citationState)?.data?.fields[0].code).toBe(code(2));
    const restored = restoreExactHistory(captureExactHistory(after)!, after.field(exactSourceState).text, extensions);
    const undone = perform(restored, undo);
    expect(undone.field(exactSourceState).text).toBe(source);
    expect(undone.field(citationState)?.data).toEqual(data);
    const redone = perform(undone, redo);
    expect(redone.field(exactSourceState).text).toBe(after.field(exactSourceState).text);
    expect(redone.field(citationState)?.data).toEqual(after.field(citationState)?.data);
  });

  it("converts embedded fields only upon accepted command, preserving source outside the carriers", () => {
    const embedded = "\uFEFF---\r\nkeep: 'unknown' # intact\n---\r\n" + encodeDocumentData(data.documentData!, null, data.acceptedFields ?? null)
      + "\r\n\r\nArgument 😀 " + encodeField(data.fields[0]) + "\nTail";
    const before = initial(embedded, snapshot(undefined));
    // Explicitly pass absent: JavaScript's default parameter would otherwise supply the fixture metadata.
    const absent = before.update({effects: setCitationSnapshot.of({...snapshot(), status: "absent", data: undefined}), annotations: Transaction.addToHistory.of(false)}).state;
    const cancelled = ZoteroMarkdownTransaction.capture(absent, context);
    cancelled.applyCallback(absent, context, {type: "getFields"});
    cancelled.cancel();
    expect(cancelled.finalize(absent, context, complete)).toBeNull();
    expect(absent.field(exactSourceState).text).toBe(embedded);
    expect(absent.field(citationState)?.data).toBeUndefined();
    const transaction = ZoteroMarkdownTransaction.capture(absent, context);
    transaction.applyCallback(absent, context, {type: "getFields"});
    const finalized = transaction.finalize(absent, context, complete)!;
    const after = commit(absent, finalized);
    expect(after.field(exactSourceState).text).toContain("](cite:cfirst)");
    expect(after.field(exactSourceState).text).not.toContain("scholium-zotero");
    expect(after.field(citationState)?.data?.fields[0].code).toBe(data.fields[0].code);
    expect(perform(after, undo).field(exactSourceState).text).toBe(embedded);
    expect(perform(after, undo).field(citationState)?.data).toBeUndefined();
  });

  it("does not accept staged migration when preferences cleanup has only read callbacks", () => {
    const embedded = "\uFEFF---\r\nkeep: 'unknown' # intact\n---\r\n" + encodeDocumentData(data.documentData!, null, data.acceptedFields ?? null)
      + "\r\n\nArgument 😀 " + encodeField(data.fields[0]) + "\nTail e\u0301\r\n";
    const absentSnapshot: ZoteroCitationSnapshot = {noteID: snapshot().noteID, vaultID: snapshot().vaultID, status: "absent"};
    const before = initial(embedded, absentSnapshot);
    const preferences = {...context, command: "setDocPrefs" as const};
    for (const reads of [[], ["getDocumentData"], ["getDocumentData", "getFields"], ["getDocumentData", "cursorInField"]] as const) {
      const transaction = ZoteroMarkdownTransaction.capture(before, preferences);
      for (const type of reads) transaction.applyCallback(before, preferences, {type});
      expect(transaction.finalize(before, preferences, complete)).toBeNull();
      expect(before.field(exactSourceState).text).toBe(embedded);
      expect(before.field(citationState)?.data).toBeUndefined();
      expect(undoDepth(before)).toBe(0);
    }
    for (const type of ["getDocumentData", "cursorInField"] as const) {
      const unverifiedRefresh = ZoteroMarkdownTransaction.capture(before, context);
      unverifiedRefresh.applyCallback(before, context, {type});
      expect(unverifiedRefresh.finalize(before, context, complete)).toBeNull();
    }
  });

  it("accepts migration after a vendor preferences write and discards it on cancellation", () => {
    const embedded = "\uFEFF" + encodeDocumentData(data.documentData!, null, data.acceptedFields ?? null)
      + "\r\n\nArgument 😀 " + encodeField(data.fields[0]) + "\nTail e\u0301\r\n";
    const absentSnapshot: ZoteroCitationSnapshot = {noteID: snapshot().noteID, vaultID: snapshot().vaultID, status: "absent"};
    const before = initial(embedded, absentSnapshot);
    const preferences = {...context, command: "setDocPrefs" as const};
    for (const value of [data.documentData!, '<data style="numeric"/>']) {
      const transaction = ZoteroMarkdownTransaction.capture(before, preferences);
      expect(transaction.applyCallback(before, preferences, {type: "getDocumentData"})).toEqual({kind: "string", value: data.documentData});
      transaction.applyCallback(before, preferences, {type: "setDocumentData", value});
      const operation = transaction.finalize(before, preferences, complete)!;
      expect(operation).not.toBeNull();
      expect(operation.source).toBe(convertEmbeddedFields(embedded).source);
      expect(operation.citationData?.documentData).toBe(value);
      const after = commit(before, operation);
      expect(undoDepth(after)).toBe(1);
      const undone = perform(after, undo);
      expect(undone.field(exactSourceState).text).toBe(embedded);
      expect(undone.field(citationState)?.data).toBeUndefined();
      const cancelled = ZoteroMarkdownTransaction.capture(before, preferences);
      cancelled.applyCallback(before, preferences, {type: "setDocumentData", value});
      expect(cancelled.finalize(before, preferences, {status: "cancelled", remoteCleanupConfirmed: true})).toBeNull();
      expect(before.field(exactSourceState).text).toBe(embedded);
      expect(before.field(citationState)?.data).toBeUndefined();
    }
  });

  it("keeps the latest disk baseline through conversion Undo, recovery, deletion save and Redo", () => {
    const embedded = encodeDocumentData(data.documentData!, null, data.acceptedFields ?? null) + "\n\n" + encodeField(data.fields[0]);
    const absentSnapshot: ZoteroCitationSnapshot = {noteID: snapshot().noteID, vaultID: snapshot().vaultID, status: "absent"};
    const before = initial(embedded, absentSnapshot);
    const conversion = convertEmbeddedFields(embedded);
    let after = commit(before, conversion);
    const committed = {...snapshot(conversion.citationData), revision: {sha256: "b".repeat(64), byteCount: 321}};
    after = after.update({effects: setCitationSnapshot.of(committed), annotations: Transaction.addToHistory.of(false)}).state;
    const undone = perform(after, undo);
    expect(undone.field(exactSourceState).text).toBe(embedded);
    expect(undone.field(citationState)?.data).toBeUndefined();
    expect(undone.field(citationState)?.baseline).toEqual(committed);
    const recovered = restoreExactHistory(captureExactHistory(undone)!, embedded, extensions);
    expect(recovered.field(citationState)?.baseline).toEqual(committed);
    expect(recovered.field(citationState)?.data).toBeUndefined();
    const deletionSaved = recovered.update({effects: setCitationSnapshot.of(absentSnapshot), annotations: Transaction.addToHistory.of(false)}).state;
    const redone = perform(deletionSaved, redo);
    expect(redone.field(citationState)?.baseline).toEqual(absentSnapshot);
    expect(redone.field(citationState)?.data).toEqual(conversion.citationData);
    expect(redone.field(exactSourceState).text).toBe(conversion.source);
    // A save completing behind later metadata input advances only the baseline.
    const newer = redone.update({effects: setCitationData.of({...conversion.citationData, documentData: "newer"})}).state;
    const rebased = newer.update({effects: [setCitationSnapshot.of(committed), setCitationData.of(newer.field(citationState)?.data)],
      annotations: Transaction.addToHistory.of(false)}).state;
    expect(rebased.field(citationState)?.baseline).toEqual(committed);
    expect(rebased.field(citationState)?.data?.documentData).toBe("newer");
  });

  it("preserves serialized Undo when a detached save advances its outer disk baseline", () => {
    const before = initial();
    const after = commit(before, stageFieldOperation(projectFieldsForState(before), {updates: [{id: "cfirst", text: "Longer changed citation"}], acceptCurrentFields: true}));
    const source = after.field(exactSourceState).text;
    const captured = captureExactHistory(after)!;
    const committed = {...snapshot(after.field(citationState)?.data), revision: {sha256: "d".repeat(64), byteCount: 432},
      sourceFingerprint: {sha256: "e".repeat(64), byteCount: new TextEncoder().encode(source).byteLength}};
    const restored = restoreExactHistory(captured, source, extensions);
    const rebased = restored.update({effects: [setCitationSnapshot.of(committed), setCitationData.of(restored.field(citationState)?.data)],
      annotations: Transaction.addToHistory.of(false)}).state;
    expect(undoDepth(rebased)).toBe(1);
    const undone = perform(rebased, undo);
    expect(undone.field(citationState)?.baseline).toEqual(committed);
    expect(undone.field(citationState)?.data).toEqual(data);
    expect(undone.field(exactSourceState).text).toBe(before.field(exactSourceState).text);
  });

  it("guards metadata revision as well as source revision during a Zotero callback sequence", () => {
    const before = initial();
    const transaction = ZoteroMarkdownTransaction.capture(before, context);
    const updated = before.update({effects: setCitationSnapshot.of(snapshot({...data, documentData: "changed"}))}).state;
    expect(() => transaction.applyCallback(updated, context, {type: "getFields"})).toThrow(/authority/);
    const staleOperation = stageFieldOperation(projectFieldsForState(before), {documentData: "new"});
    expect(fieldOperationTransaction(updated, staleOperation)).toBeNull();
  });

  it("retains removed field data for Undo and marks a known source deletion stale", () => {
    const before = initial();
    const field = projectFieldsForState(before).fields[0];
    const from = normalizedDocumentText(source.slice(0, field.range.from)).length;
    const to = normalizedDocumentText(source.slice(0, field.range.to)).length;
    const deleted = before.update({changes: {from, to}}).state;
    expect(deleted.field(citationState)?.data).toEqual(data);
    expect(projectFieldsForState(deleted).fields).toEqual([]);
    expect(projectFieldsForState(deleted).citationStateStale).toBe(true);
    expect(projectFieldsForState(perform(deleted, undo)).fields[0].id).toBe("cfirst");
  });

  it("refreshes an empty citation list after deletion without changing source or merging its Undo", () => {
    const before = initial(), field = projectFieldsForState(before).fields[0];
    const from = normalizedDocumentText(source.slice(0, field.range.from)).length;
    const to = normalizedDocumentText(source.slice(0, field.range.to)).length;
    const deleted = before.update({changes: {from, to}, userEvent: "delete.backward"}).state;
    const deletedSource = deleted.field(exactSourceState).text;
    expect(projectFieldsForState(deleted).citationStateStale).toBe(true);

    const refresh = ZoteroMarkdownTransaction.capture(deleted, context);
    expect(refresh.applyCallback(deleted, context, {type: "getFields"})).toEqual({kind: "fields", value: []});
    const operation = refresh.finalize(deleted, context, complete)!;
    expect(operation).not.toBeNull();
    expect(operation.changes).toEqual([]);
    const refreshed = commit(deleted, operation);
    expect(refreshed.field(exactSourceState).text).toBe(deletedSource);
    expect(refreshed.field(citationState)?.data).toEqual({...data, fields: [], acceptedFields: []});
    expect(projectFieldsForState(refreshed).citationStateStale).toBe(false);
    expect(undoDepth(refreshed)).toBe(2);

    const undone = perform(refreshed, undo);
    expect(undone.field(exactSourceState).text).toBe(deletedSource);
    expect(undone.field(citationState)?.data).toEqual(data);
    expect(projectFieldsForState(undone).citationStateStale).toBe(true);
    expect(perform(undone, undo).field(exactSourceState).text).toBe(source);
    expect(perform(undone, redo).field(citationState)?.data).toEqual(refreshed.field(citationState)?.data);
  });

  it("does not treat a prose cite: mention as an occurrence but rejects reserved links in unsupported contexts", () => {
    const text = "Use cite: identifiers in this discussion.";
    expect(projectFields(text, data).diagnostics).toEqual([]);
    for (const wrapped of ["# [Visible](cite:cfirst)", "> [Visible](cite:cfirst)", "- [Visible](cite:cfirst)", "![Visible](cite:cfirst)", "<cite:cfirst>"]) {
      expect(projectFields(wrapped, data).diagnostics.length).toBeGreaterThan(0);
    }
  });

  it("converts only bibliography marker bytes across mixed separators and exact fallback", () => {
    const field = {id: "cbib", kind: "bibliography" as const, code: 'BIBL {} CSL_BIBLIOGRAPHY', text: "Book."};
    const carrier = encodeField(field);
    const openingEnd = carrier.indexOf("-->") + 3;
    const closingFrom = carrier.lastIndexOf("<!--/");
    const mixed = carrier.slice(0, openingEnd) + "\r\n\nManually edited 😀 e\u0301\\.\n\r\n" + carrier.slice(closingFrom);
    const converted = convertEmbeddedFields(mixed);
    expect(converted.source).toBe("<!--cite-bibliography:cbib-->\r\n\nManually edited 😀 e\u0301\\.\n\r\n<!--/cite-bibliography-->");
    expect(converted.citationData.fields[0].text).toBe("Book.");
    expect(converted.changes).toHaveLength(2);
  });

  it("converts a bibliography with exact fallback and durable association", () => {
    const field = {id: "cbib", kind: "bibliography" as const, code: 'BIBL {"uncited":[]} CSL_BIBLIOGRAPHY', text: "<p>First.</p><p>Second.</p>"};
    const embedded = encodeDocumentData("opaque data") + "\r\n\r\n" + encodeField(field, "\r\n");
    const converted = convertEmbeddedFields(embedded);
    expect(converted.source).toBe("\r\n\r\n<!--cite-bibliography:cbib-->\r\n\r\nFirst\\.\r\n\r\nSecond\\.\r\n\r\n<!--/cite-bibliography-->");
    expect(projectFields(converted.source, converted.citationData).fields[0]).toMatchObject({id: "cbib", code: field.code, text: "First.Second."});
  });
});

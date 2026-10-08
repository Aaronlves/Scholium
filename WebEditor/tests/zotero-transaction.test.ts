import {EditorState, Transaction} from "@codemirror/state";
import {history, redo, undo, undoDepth} from "@codemirror/commands";
import {DOMParser} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {encodeDocumentData, encodeField, fieldOperationTransaction, projectFields, stageFieldOperation} from "../zotero-fields";
import {ZoteroMarkdownTransaction, unsupportedNoteCitationStyleMessage, validZoteroCallback, type ZoteroCallback, type ZoteroCallbackReply,
  type ZoteroTransactionCapture} from "../zotero-transaction";
import {renderedFormatting, unrepresentableVendorBlocks, unrepresentableVendorFormatting, vendorFormattingFixtures} from "./zotero-formatting-fixtures";

vi.stubGlobal("DOMParser", DOMParser);
const code = (id: number, plain = "[1]", extra = "") => `ITEM CSL_CITATION {"citationID":"vendor-${id}","citationItems":[{"id":${id},"uris":["http://zotero.org/users/12/items/ITEM0001"]}],"properties":{"plainCitation":${JSON.stringify(plain)}${extra}}}`;
const bibCode = 'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY';
const context: ZoteroTransactionCapture = {transactionID: "01234567-89AB-CDEF-0123-456789ABCDEF", command: "addEditCitation",
  mode: "livePreview", interactionRevision: 7, compositionRevision: 3, composing: false};
const complete = {status: "cleanedUp", remoteCleanupConfirmed: true} as const;
function fixture() {
  const raw = "\uFEFF---\r\nunknown: 'keep' # source\n---\r\n" + encodeDocumentData("<data style='numeric' />") + "\r\nArgument 😀 "
    + encodeField({id: "first", kind: "citation", code: code(1), text: "[1]"}) + "\nSecond "
    + encodeField({id: "second", kind: "citation", code: code(2, "[2]"), text: "[2]"}) + "\r\nInsert @new here.\n\n"
    + encodeField({id: "bib", kind: "bibliography", code: bibCode, text: '<div class="csl-bib-body"><div class="csl-entry">First book.</div><div class="csl-entry">Second book.</div></div>'})
    + "\r\nUnchanged tail no newline";
  return stageFieldOperation(projectFields(raw), {acceptCurrentFields: true}).source;
}
function initial(source: string, anchor = normalizedDocumentText(source).indexOf("@new") + 4, head = anchor) {
  return EditorState.create({doc: normalizedDocumentText(source), selection: {anchor, head},
    extensions: [history(), exactSourceHistory, EditorState.lineSeparator.of("\n")]})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
}
function reference(source: string) {
  const from = normalizedDocumentText(source).indexOf("@new");
  return {from, to: from + 4, expected: "@new"};
}
function newField(reply: ZoteroCallbackReply) {
  expect(reply.kind).toBe("field");
  if (reply.kind !== "field" || !reply.value) throw new Error("Expected inserted field");
  return reply.value;
}
function commit(state: EditorState, operation: NonNullable<ReturnType<ZoteroMarkdownTransaction["finalize"]>>) {
  const spec = fieldOperationTransaction(state, operation);
  expect(spec).not.toBeNull();
  return state.update({...spec!, selection: operation.selection}).state;
}
function perform(state: EditorState, command: typeof undo) {
  let next = state;
  expect(command({state, dispatch: transaction => {next = transaction.state;}})).toBe(true);
  return next;
}

describe("source-owned Zotero callback transaction", () => {
  it("accepts a new citation when the opaque WebKit origin has no randomUUID", () => {
    const originalCrypto = globalThis.crypto;
    const randomBytes = vi.fn((bytes: Uint8Array<ArrayBuffer>) => originalCrypto.getRandomValues(bytes));
    vi.stubGlobal("crypto", {getRandomValues: randomBytes});
    try {
      expect(typeof crypto.randomUUID).toBe("undefined");
      const source = fixture(), state = initial(source);
      const capture = {...context, referenceRange: reference(source)};
      const transaction = ZoteroMarkdownTransaction.capture(state, capture);
      const inserted = newField(transaction.applyCallback(state, capture, {type: "insertField"}));
      expect(inserted.id).toMatch(/^host_[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/);
      expect(randomBytes).toHaveBeenCalledTimes(1);
      transaction.applyCallback(state, capture, {type: "setFieldCode", id: inserted.id, code: code(3)});
      transaction.applyCallback(state, capture, {type: "setFieldText", id: inserted.id, html: "[3]"});
      const operation = transaction.finalize(state, capture, complete)!;
      expect(operation).not.toBeNull();
      expect(projectFields(operation.source).fields.find(field => field.id === inserted.id)?.text).toBe("[3]");
      expect(projectFields(operation.source).citationStateStale).toBe(false);
      expect(state.field(exactSourceState).text).toBe(source);
    } finally {
      vi.stubGlobal("crypto", originalCrypto);
    }
    expect(globalThis.crypto).toBe(originalCrypto);
  });

  it("consumes @query, updates all fields/docdata/layout, and commits as one exact Undo/Redo", () => {
    const source = fixture(), state = initial(source);
    const capture = {...context, referenceRange: reference(source)};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    const apply = (callback: ZoteroCallback) => transaction.applyCallback(state, context, callback);
    expect(apply({type: "getFields"})).toMatchObject({kind: "fields", value: [
      {id: "first", text: "[1]"}, {id: "second", text: "[2]"}, {id: "bib", text: "First book.Second book."},
    ]});
    expect(apply({type: "canInsertField"})).toEqual({kind: "boolean", value: true});
    apply({type: "setDocumentData", value: "\r\n<data style='author-date' future='keep' />\n"});
    const inserted = newField(apply({type: "insertField"}));
    expect(inserted).toMatchObject({code: "", text: "{Citation}", noteIndex: 0});
    apply({type: "setFieldCode", id: inserted.id, code: "TEMP"});
    apply({type: "setFieldText", id: inserted.id, html: "(New, 2026)"});
    apply({type: "setFieldCode", id: inserted.id, code: code(3, "(New, 2026)")});
    apply({type: "setFieldText", id: "first", html: "(First, 2024)"});
    apply({type: "setFieldCode", id: "first", code: code(1, "(First, 2024)")});
    apply({type: "setFieldText", id: "second", html: "(Second, 2025)"});
    apply({type: "setFieldCode", id: "second", code: code(2, "(Second, 2025)")});
    apply({type: "setBibliographyStyle", style: {firstLineIndent: -720, indent: 720, lineSpacing: 240, entrySpacing: 120, tabStops: [720]}});
    apply({type: "setFieldText", id: "bib", html: '<div class="csl-bib-body"><div class="csl-entry"><i>First book.</i></div><div class="csl-entry">Second book.</div><div class="csl-entry">New book.</div></div>'});
    expect(state.field(exactSourceState).text).toBe(source);
    expect(undoDepth(state)).toBe(0);
    const operation = transaction.finalize(state, context, complete)!;
    expect(operation).not.toBeNull();
    expect(operation.changes.some(change => change.from > 0)).toBe(true);
    expect(operation.source).not.toContain("@new");
    expect(operation.source.startsWith("\uFEFF---\r\nunknown: 'keep' # source\n---\r\n")).toBe(true);
    expect(operation.source.endsWith("\r\nUnchanged tail no newline")).toBe(true);
    const projection = projectFields(operation.source);
    expect(projection.fields.map(field => field.id)).toEqual(["first", "second", inserted.id, "bib"]);
    expect(projection.acceptedFields).toEqual(projection.fields.map(({id, code}) => ({id, code})));
    expect(projection.citationStateStale).toBe(false);
    expect(projection.documentData).toBe("\r\n<data style='author-date' future='keep' />\n");
    let current = commit(state, operation);
    expect(current.field(exactSourceState).text).toBe(operation.source);
    expect(undoDepth(current)).toBe(1);
    expect(current.selection.main.anchor).toBe(operation.selection?.anchor);
    current = perform(current, undo);
    expect(current.field(exactSourceState).text).toBe(source);
    expect(current.selection.main.anchor).toBe(state.selection.main.anchor);
    current = perform(current, redo);
    expect(current.field(exactSourceState).text).toBe(operation.source);
  });

  it("edits a current citation and stages selection intent without moving the live caret", () => {
    const source = fixture(), projected = projectFields(source);
    const from = normalizedDocumentText(source.slice(0, projected.fields[1].fallbackRange.from)).length;
    const state = initial(source, from);
    const transaction = ZoteroMarkdownTransaction.capture(state, context);
    expect(transaction.applyCallback(state, context, {type: "cursorInField"})).toMatchObject({kind: "field", value: {id: "second"}});
    transaction.applyCallback(state, context, {type: "setFieldCode", id: "second", code: code(4, "[4]")});
    transaction.applyCallback(state, context, {type: "setFieldText", id: "second", html: "[4]"});
    expect(transaction.applyCallback(state, context, {type: "selectField", id: "first"})).toEqual({kind: "selection", fieldID: "first"});
    expect(state.selection.main.anchor).toBe(from);
    expect(transaction.applyCallback(state, context, {type: "cursorInField"})).toMatchObject({kind: "field", value: {id: "first"}});
    const operation = transaction.finalize(state, context, complete)!;
    expect(projectFields(operation.source).fields.map(field => field.id)).toEqual(["first", "second", "bib"]);
    expect(projectFields(operation.source).fields[1].text).toBe("[4]");
  });

  it.each(vendorFormattingFixtures)("stages and finalizes $name with faithful formatting in one Undo", ({html, kind, paragraphs}) => {
    const source = fixture(), field = projectFields(source).fields.find(field => field.kind === kind)!;
    const from = normalizedDocumentText(source.slice(0, field.fallbackRange.from)).length;
    const state = initial(source, from);
    const capture = {...context, command: kind === "citation" ? "addEditCitation" as const : "addEditBibliography" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    transaction.applyCallback(state, capture, {type: "setFieldText", id: field.id, html});
    expect(transaction.applyCallback(state, capture, {type: "getFieldText", id: field.id})).toEqual({kind: "string",
      value: paragraphs.flatMap(runs => runs.map(([text]) => text)).join("")});
    expect(state.field(exactSourceState).text).toBe(source);
    expect(undoDepth(state)).toBe(0);
    expect(state.selection.main.anchor).toBe(from);
    const operation = transaction.finalize(state, capture, complete)!;
    const projection = projectFields(operation.source), accepted = projection.fields.find(value => value.id === field.id)!;
    expect(projection.diagnostics).toEqual([]);
    expect(projection.citationStateStale).toBe(false);
    expect(accepted).toMatchObject({cachedText: html, manualTextChanged: false});
    expect(renderedFormatting(operation.source.slice(accepted.fallbackRange.from, accepted.fallbackRange.to))).toEqual(paragraphs);
    expect(operation.source.startsWith("\uFEFF---\r\nunknown: 'keep' # source\n---\r\n")).toBe(true);
    expect(operation.source.endsWith("\r\nUnchanged tail no newline")).toBe(true);
    let current = commit(state, operation);
    expect(current.field(exactSourceState).text).toBe(operation.source);
    expect(undoDepth(current)).toBe(1);
    current = perform(current, undo);
    expect(current.field(exactSourceState).text).toBe(source);
    expect(current.selection.eq(state.selection)).toBe(true);
    current = perform(current, redo);
    expect(current.field(exactSourceState).text).toBe(operation.source);
  });

  it.each([
    ...unrepresentableVendorFormatting.map(html => ({html, bibliography: false})),
    ...unrepresentableVendorBlocks.map(html => ({html, bibliography: true})),
  ])("refuses setFieldText without publishing prior callbacks or changing source/Undo ($html)", ({html, bibliography}) => {
    const original = fixture();
    const state = initial(original).update({changes: {from: normalizedDocumentText(original).length, insert: " researcher edit"}}).state;
    const source = state.field(exactSourceState).text;
    const capture: ZoteroTransactionCapture = bibliography ? {...context, command: "addEditBibliography"}
      : {...context, referenceRange: reference(source)};
    expect(undoDepth(state)).toBe(1);
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    const id = bibliography ? "bib" : newField(transaction.applyCallback(state, capture, {type: "insertField"})).id;
    transaction.applyCallback(state, capture, {type: "setFieldCode", id, code: bibliography ? bibCode : code(3)});
    transaction.applyCallback(state, capture, {type: "setDocumentData", value: "<data staged='unpublished' />"});
    expect(() => transaction.applyCallback(state, capture, {type: "setFieldText", id, html})).toThrow(/formatting fidelity/);
    expect(() => transaction.finalize(state, capture, complete)).toThrow(/authority/);
    expect(() => transaction.applyCallback(state, capture, {type: "setFieldText", id, html: "[3]"})).toThrow(/authority/);
    expect(state.field(exactSourceState).text).toBe(source);
    expect(state.field(exactSourceState).text).toContain("@new");
    expect(state.selection.main.anchor).toBe(reference(source).to);
    expect(undoDepth(state)).toBe(1);
    expect(perform(state, undo).field(exactSourceState).text).toBe(original);
  });

  it("consumes existing multiword Unicode @query grammar only after accepted insertion", () => {
    const query = "@ethics agency 道德", source = encodeDocumentData("<data />") + "\r\nArgument " + query + " tail.";
    const from = normalizedDocumentText(source).indexOf(query), state = initial(source, from + query.length);
    const capture = {...context, referenceRange: {from, to: from + query.length, expected: query}};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    const inserted = newField(transaction.applyCallback(state, capture, {type: "insertField"}));
    transaction.applyCallback(state, capture, {type: "setFieldCode", id: inserted.id, code: code(3)});
    transaction.applyCallback(state, capture, {type: "setFieldText", id: inserted.id, html: "[3]"});
    expect(state.field(exactSourceState).text).toBe(source);
    const operation = transaction.finalize(state, capture, complete)!;
    expect(operation.source).not.toContain(query);
    expect(operation.source.endsWith(" tail.")).toBe(true);
  });

  it("admits 512 UTF-16 query units after @ and rejects longer completion captures", () => {
    for (const count of [512, 513]) {
      const query = "@" + "a".repeat(count), source = "Argument " + query;
      const from = source.indexOf("@"), state = initial(source, source.length);
      const capture = {...context, referenceRange: {from, to: source.length, expected: query}};
      const create = () => ZoteroMarkdownTransaction.capture(state, capture);
      if (count === 512) expect(create().originalSource).toBe(source);
      else expect(create).toThrow(/completion/);
    }
  });

  it("bibliography editing targets the last existing bibliography regardless of the captured caret", () => {
    const source = fixture(), state = initial(source);
    const capture = {...context, command: "addEditBibliography" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    transaction.applyCallback(state, capture, {type: "setFieldText", id: "bib", html: '<div class="csl-bib-body"><div class="csl-entry">Updated references.</div></div>'});
    const operation = transaction.finalize(state, capture, complete)!;
    expect(projectFields(operation.source).fields.at(-1)).toMatchObject({id: "bib", kind: "bibliography", text: "Updated references."});
  });

  it("first bibliography insertion and retained layout are accepted with actual Zotero field code", () => {
    const source = encodeDocumentData("<data />") + "\r\nEnd.", state = initial(source, normalizedDocumentText(source).length);
    const capture = {...context, command: "addEditBibliography" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    const inserted = newField(transaction.applyCallback(state, capture, {type: "insertField"}));
    transaction.applyCallback(state, capture, {type: "setFieldCode", id: inserted.id, code: bibCode});
    transaction.applyCallback(state, capture, {type: "setBibliographyStyle", style: {firstLineIndent: -720, indent: 720, lineSpacing: 240, entrySpacing: 0, tabStops: []}});
    transaction.applyCallback(state, capture, {type: "setFieldText", id: inserted.id, html: '<div class="csl-bib-body"><div class="csl-entry">Reference.</div></div>'});
    const operation = transaction.finalize(state, capture, complete)!;
    expect(projectFields(operation.source).fields[0].code).toBe(bibCode);
    expect(projectFields(operation.source).bibliographyStyle?.firstLineIndent).toBe(-720);
  });

  it("accepts Zotero replacing a citation occurrence with the first bibliography", () => {
    const source = encodeDocumentData("<data />") + "\nArgument " + encodeField({id: "first", kind: "citation", code: code(1), text: "[1]"}) + " tail.";
    const field = projectFields(source).fields[0], from = normalizedDocumentText(source.slice(0, field.fallbackRange.from)).length;
    const state = initial(source, from), capture = {...context, command: "addEditBibliography" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    expect(transaction.applyCallback(state, capture, {type: "cursorInField"})).toMatchObject({kind: "field", value: {id: "first"}});
    transaction.applyCallback(state, capture, {type: "setFieldCode", id: "first", code: bibCode});
    transaction.applyCallback(state, capture, {type: "setFieldText", id: "first", html: '<div class="csl-bib-body"><div class="csl-entry">Reference.</div></div>'});
    const operation = transaction.finalize(state, capture, complete)!;
    expect(projectFields(operation.source).fields).toMatchObject([{id: "first", kind: "bibliography", code: bibCode, text: "Reference."}]);
  });

  it("complete alone and explicit cancellation are quiet; unknown cleanup and residual TEMP fields fail", () => {
    const source = fixture(), state = initial(source);
    const alone = ZoteroMarkdownTransaction.capture(state, context);
    expect(alone.finalize(state, context, complete)).toBeNull();
    for (const remote of [{status: "cancelled", remoteCleanupConfirmed: true}, {status: "unknown", remoteCleanupConfirmed: false}] as const) {
      const transaction = ZoteroMarkdownTransaction.capture(state, {...context, referenceRange: reference(source)});
      const inserted = newField(transaction.applyCallback(state, context, {type: "insertField"}));
      transaction.applyCallback(state, context, {type: "setFieldCode", id: inserted.id, code: code(3)});
      transaction.applyCallback(state, context, {type: "setFieldText", id: inserted.id, html: "[3]"});
      if (remote.status === "cancelled") expect(transaction.finalize(state, context, remote)).toBeNull();
      else expect(() => transaction.finalize(state, context, remote)).toThrow(/cleanup/);
    }
    const pending = ZoteroMarkdownTransaction.capture(state, {...context, referenceRange: reference(source)});
    const inserted = newField(pending.applyCallback(state, context, {type: "insertField"}));
    pending.applyCallback(state, context, {type: "setFieldCode", id: inserted.id, code: "TEMP"});
    expect(() => pending.finalize(state, context, complete)).toThrow(/incomplete/);
    expect(state.field(exactSourceState).text).toBe(source);
    expect(undoDepth(state)).toBe(0);
  });

  it.each(["selection", "source", "mode", "interaction", "composition", "composing", "transaction"])("rejects %s changes and cannot revive authority", change => {
    const source = fixture(), state = initial(source);
    const transaction = ZoteroMarkdownTransaction.capture(state, context);
    let current = state, ctx = {...context};
    if (change === "selection") current = state.update({selection: {anchor: state.selection.main.head + 1}}).state;
    if (change === "source") current = state.update({changes: {from: state.doc.length, insert: "Later"}}).state;
    if (change === "mode") ctx.mode = "source";
    if (change === "interaction") ctx.interactionRevision++;
    if (change === "composition") ctx.compositionRevision++;
    if (change === "composing") ctx.composing = true;
    if (change === "transaction") ctx.transactionID = "different";
    expect(() => transaction.applyCallback(current, ctx, {type: "getFields"})).toThrow(/authority/);
    expect(() => transaction.finalize(state, context, complete)).toThrow(/authority/);
  });

  it("Zotero deleting its new TEMP placeholder cancels without consuming the captured @query", () => {
    const source = fixture(), state = initial(source), capture = {...context, referenceRange: reference(source)};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    const inserted = newField(transaction.applyCallback(state, capture, {type: "insertField"}));
    transaction.applyCallback(state, capture, {type: "setFieldCode", id: inserted.id, code: "TEMP"});
    transaction.applyCallback(state, capture, {type: "deleteField", id: inserted.id});
    expect(transaction.finalize(state, capture, complete)).toBeNull();
    expect(state.field(exactSourceState).text).toBe(source);
    expect(state.field(exactSourceState).text).toContain("@new");
    expect(undoDepth(state)).toBe(0);
  });

  it("an observed unchanged refresh is quiet, while an unverified changed refresh fails", () => {
    const source = fixture(), state = initial(source), capture = {...context, command: "refresh" as const};
    const unchanged = ZoteroMarkdownTransaction.capture(state, capture);
    unchanged.applyCallback(state, capture, {type: "getFields"});
    expect(unchanged.finalize(state, capture, complete)).toBeNull();
    const unverified = ZoteroMarkdownTransaction.capture(state, capture);
    unverified.applyCallback(state, capture, {type: "setDocumentData", value: "<data changed='true' />"});
    expect(() => unverified.finalize(state, capture, complete)).toThrow(/verify/);
  });

  it("preserves a citation before its bibliography through Zotero's refresh deletion transcript", () => {
    const citation = {id: "cite", kind: "citation" as const, code: code(1), text: "[1]"};
    const bibliography = {id: "bib", kind: "bibliography" as const, code: bibCode,
      text: '<div class="csl-bib-body"><div class="csl-entry">First book.</div></div>'};
    const source = encodeDocumentData("<data style='apa' />", null, [citation, bibliography].map(({id, code}) => ({id, code})))
      + "\r\n\r\nArgument 😀 " + encodeField(citation) + "\r\n\r\n" + encodeField(bibliography, "\r\n") + "\r\nTail é";
    const state = initial(source, 0), capture = {...context, command: "refresh" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    const reply = transaction.applyCallback(state, capture, {type: "getFields"});
    if (reply.kind !== "fields") throw new Error("Expected ordered manuscript fields");
    // Zotero 10.0.5 _processFields marks ITEM fields with adjacent=true for deletion;
    // a following bibliography never receives the pending citation merge.
    const deletions = reply.value.filter(field => field.code.startsWith("ITEM CSL_CITATION ") && field.adjacent);
    transaction.applyCallback(state, capture, {type: "setFieldCode", id: "bib", code: bibCode});
    transaction.applyCallback(state, capture, {type: "setFieldText", id: "bib", html: bibliography.text});
    for (const field of deletions.reverse()) transaction.applyCallback(state, capture, {type: "deleteField", id: field.id});
    const operation = transaction.finalize(state, capture, complete);
    const current = operation ? commit(state, operation) : state;
    expect(projectFields(current.field(exactSourceState).text).fields.map(field => field.id)).toEqual(["cite", "bib"]);
    expect(current.field(exactSourceState).text).toBe(source);
    expect(undoDepth(current)).toBe(0);
  });

  it("lets Zotero merge three touching citations into the final occurrence in one exact Undo", () => {
    const fields = [1, 2, 3].map(id => ({id: `cite_${id}`, kind: "citation" as const, code: code(id, `[${id}]`), text: `[${id}]`}));
    const source = encodeDocumentData("<data style='numeric' />", null, fields.map(({id, code}) => ({id, code})))
      + "\n\nArgument 😀 " + fields.map(field => encodeField(field)).join("") + " tail é";
    const state = initial(source, 0), capture = {...context, command: "refresh" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    const reply = transaction.applyCallback(state, capture, {type: "getFields"});
    if (reply.kind !== "fields") throw new Error("Expected ordered manuscript fields");
    const deletions = [];
    for (const field of reply.value) {
      if (field.adjacent) { deletions.push(field.id); continue; }
      transaction.applyCallback(state, capture, {type: "setFieldCode", id: field.id,
        code: 'ITEM CSL_CITATION {"citationID":"merged","citationItems":[{"id":1},{"id":2},{"id":3}]}' });
      transaction.applyCallback(state, capture, {type: "setFieldText", id: field.id, html: "[1–3]"});
    }
    for (const id of deletions.reverse()) transaction.applyCallback(state, capture, {type: "deleteField", id});
    let current = commit(state, transaction.finalize(state, capture, complete)!);
    const catalog = projectFields(current.field(exactSourceState).text);
    expect(catalog.fields.map(field => ({id: field.id, text: field.text}))).toEqual([{id: "cite_3", text: "[1–3]"}]);
    expect(catalog.citationStateStale).toBe(false);
    expect(undoDepth(current)).toBe(1);
    current = perform(current, undo);
    expect(current.field(exactSourceState).text).toBe(source);
  });

  it.each([
    '<data data-version="3"><prefs><pref name="noteType" value="1"/></prefs></data>',
    '<data data-version="3"><prefs><pref name="noteType" value="2"/></prefs></data>',
    '{"dataVersion":4,"prefs":{"noteType":1}}',
    '{"dataVersion":4,"prefs":{"noteType":2}}',
  ])("refuses note-style document preferences before an empty manuscript can commit (%s)", data => {
    const source = "Argument 😀\r\n", state = initial(source, normalizedDocumentText(source).length);
    const capture = {...context, command: "setDocPrefs" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    expect(() => transaction.applyCallback(state, capture, {type: "setDocumentData", value: data})).toThrow(unsupportedNoteCitationStyleMessage);
    expect(() => transaction.finalize(state, capture, complete)).toThrow(/authority/);
    expect(state.field(exactSourceState).text).toBe(source);
    expect(undoDepth(state)).toBe(0);
  });

  it.each([
    '\uFEFF<?xml version="1.0"?>\r\n<data data-version="3" future="keep"><prefs><pref name="noteType" value="0"/><pref name="unknown" value="opaque"/></prefs></data>\n',
    ' { "dataVersion": 4, "prefs": { "noteType": 0, "unknown": [1, 2] }, "future": "keep" }\r\n',
    'vendor opaque: future unknown 😀\r\n',
  ])("retains supported zero-note preferences and opaque vendor data exactly (%s)", data => {
    const source = "Argument 😀\r\n", state = initial(source, normalizedDocumentText(source).length);
    const capture = {...context, command: "setDocPrefs" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    expect(transaction.applyCallback(state, capture, {type: "setDocumentData", value: data})).toEqual({kind: "none"});
    expect(transaction.applyCallback(state, capture, {type: "getDocumentData"})).toEqual({kind: "string", value: data});
    const operation = transaction.finalize(state, capture, complete)!;
    expect(projectFields(operation.source).documentData).toBe(data);
    expect(state.field(exactSourceState).text).toBe(source);
  });

  it("refuses DTDs and parser errors in standard XML document preferences", () => {
    const source = "Argument", state = initial(source, source.length), capture = {...context, command: "setDocPrefs" as const};
    const withDTD = ZoteroMarkdownTransaction.capture(state, capture);
    expect(() => withDTD.applyCallback(state, capture, {type: "setDocumentData", value: '<!DOCTYPE data [<!ENTITY future "keep">]><data><prefs/></data>'})).toThrow(/preferences are invalid/);
    const errorDocument = new DOMParser().parseFromString("<parsererror>Invalid XML</parsererror>", "text/xml");
    const parser = vi.spyOn(DOMParser.prototype, "parseFromString").mockReturnValueOnce(errorDocument);
    try {
      const malformed = ZoteroMarkdownTransaction.capture(state, capture);
      expect(() => malformed.applyCallback(state, capture, {type: "setDocumentData", value: "<data><prefs>"})).toThrow(/preferences are invalid/);
    } finally {parser.mockRestore();}
    expect(state.field(exactSourceState).text).toBe(source);
    expect(undoDepth(state)).toBe(0);
  });

  it("cancel drops source authority and leaves the original completion text/history untouched", () => {
    const source = fixture(), state = initial(source);
    const transaction = ZoteroMarkdownTransaction.capture(state, {...context, referenceRange: reference(source)});
    transaction.applyCallback(state, context, {type: "insertField"});
    transaction.cancel();
    expect(() => transaction.applyCallback(state, context, {type: "getFields"})).toThrow(/authority/);
    expect(transaction.finalize(state, context, complete)).toBeNull();
    expect(state.field(exactSourceState).text).toBe(source);
    expect(undoDepth(state)).toBe(0);
  });

  it("reports actual manual fallback and permits Zotero's explicit dontUpdate choice", () => {
    const original = fixture(), field = projectFields(original).fields[0];
    const source = original.slice(0, field.fallbackRange.from) + "Manual visible citation" + original.slice(field.fallbackRange.to);
    const state = initial(source), capture = {...context, command: "refresh" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    expect(transaction.applyCallback(state, capture, {type: "getFieldText", id: "first"})).toEqual({kind: "string", value: "Manual visible citation"});
    transaction.applyCallback(state, capture, {type: "getFields"});
    transaction.applyCallback(state, capture, {type: "setFieldCode", id: "first", code: code(1, "[1]", ',"dontUpdate":true')});
    const operation = transaction.finalize(state, capture, complete)!;
    expect(projectFields(operation.source).fields[0]).toMatchObject({text: "Manual visible citation", manualTextChanged: true});
    expect(projectFields(operation.source).citationStateStale).toBe(false);
  });

  it("delete and unlink differ visibly, and only final acceptance updates membership signature", () => {
    const source = fixture(), state = initial(source), capture = {...context, command: "refresh" as const};
    const transaction = ZoteroMarkdownTransaction.capture(state, capture);
    transaction.applyCallback(state, capture, {type: "getFields"});
    transaction.applyCallback(state, capture, {type: "removeFieldCode", id: "first"});
    transaction.applyCallback(state, capture, {type: "deleteField", id: "second"});
    const operation = transaction.finalize(state, capture, complete)!;
    const projection = projectFields(operation.source);
    expect(projection.fields.map(field => field.id)).toEqual(["bib"]);
    const before = projectFields(source);
    expect(operation.source).toContain(source.slice(before.fields[0].fallbackRange.from, before.fields[0].fallbackRange.to));
    expect(operation.source).not.toContain(source.slice(before.fields[1].fallbackRange.from, before.fields[1].fallbackRange.to));
    expect(projection.acceptedFields?.map(field => field.id)).toEqual(["bib"]);
  });

  it("invalid source/duplicate IDs, protected insertion and unrecognized callbacks fail closed", () => {
    const source = fixture(), field = projectFields(source).fields[0];
    const duplicate = source + "\n" + source.slice(field.range.from, field.range.to);
    expect(() => ZoteroMarkdownTransaction.capture(initial(duplicate), context)).toThrow(/recovery/);
    const codeSource = "```\n@new\n```";
    const state = initial(codeSource), transaction = ZoteroMarkdownTransaction.capture(state, {...context, referenceRange: reference(codeSource)});
    expect(transaction.applyCallback(state, context, {type: "canInsertField"})).toEqual({kind: "boolean", value: false});
    expect(() => transaction.applyCallback(state, context, {type: "insertField"})).toThrow();
    expect(validZoteroCallback({type: "setFieldText", id: "first", html: "safe", extra: true})).toBe(false);
    expect(validZoteroCallback({type: "importDocument"})).toBe(false);
    expect(validZoteroCallback({type: "setBibliographyStyle", style: {firstLineIndent: 0, indent: 0, lineSpacing: 240, entrySpacing: 0, tabStops: [Infinity]}})).toBe(false);
    for (const [lineSpacing, entrySpacing] of [[0, 0], [-240, 0], [240, -1]]) {
      expect(validZoteroCallback({type: "setBibliographyStyle", style: {firstLineIndent: 0, indent: 0, lineSpacing, entrySpacing, tabStops: []}})).toBe(false);
    }
    expect(validZoteroCallback({type: "setBibliographyStyle", style: {firstLineIndent: -720, indent: 720, lineSpacing: 240, entrySpacing: 0, tabStops: []}})).toBe(true);
  });
});

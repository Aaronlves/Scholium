import {ChangeSet, EditorState, Text} from "@codemirror/state";
import {exactSourceState} from "./exact-source-history";
import {boundedUUID} from "./uuid";
import {exactOffsetForNormalizedOffset, normalizedDocumentText} from "./state";
import {isCompletedFieldCode, projectFields, stageFieldOperation,
  type BibliographyStyle, type FieldOperation, type ProjectedField, type SourceReplacement,
  type StagedFieldOperation} from "./zotero-fields";

export type ZoteroTransactionCommand = "addEditCitation" | "addEditBibliography" | "refresh" | "setDocPrefs";
export const unsupportedNoteCitationStyleMessage = "Footnote and endnote citation styles are unavailable. Your text was preserved.";
export interface ZoteroTransactionContext {
  transactionID: string;
  mode: "livePreview" | "source";
  interactionRevision: number;
  compositionRevision: number;
  composing: boolean;
}
export interface ZoteroTransactionCapture extends ZoteroTransactionContext {
  command: ZoteroTransactionCommand;
  /** Completion ranges use CodeMirror's normalized UTF-16 coordinates. */
  referenceRange?: {from: number; to: number; expected: string};
}
export interface ZoteroCallbackField {
  id: string; code: string; text: string; noteIndex: 0; adjacent: boolean;
}
export type ZoteroCallback =
  | {type: "canInsertField" | "getDocumentData" | "cursorInField" | "insertField" | "getFields"}
  | {type: "setDocumentData"; value: string}
  | {type: "setBibliographyStyle"; style: BibliographyStyle}
  | {type: "deleteField" | "selectField" | "removeFieldCode" | "getFieldText"; id: string}
  | {type: "setFieldCode"; id: string; code: string}
  | {type: "setFieldText"; id: string; html: string};
export type ZoteroCallbackReply =
  | {kind: "none"}
  | {kind: "boolean"; value: boolean}
  | {kind: "string"; value: string}
  | {kind: "field"; value: ZoteroCallbackField | null}
  | {kind: "fields"; value: ZoteroCallbackField[]}
  | {kind: "selection"; fieldID: string};
export interface ZoteroRemoteCompletion {
  status: "cleanedUp" | "cancelled" | "unavailable" | "failed" | "busy" | "unknown";
  remoteCleanupConfirmed: boolean;
}
export interface FinalizedZoteroOperation extends StagedFieldOperation {
  selection?: {anchor: number; head: number};
}

const commands = new Set<ZoteroTransactionCommand>(["addEditCitation", "addEditBibliography", "refresh", "setDocPrefs"]);
function identifier(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_-]{0,127}$/.test(value);
}
function transactionIdentifier(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 128 && !/[\x00-\x1f\x7f]/.test(value);
}
function keys(value: object, expected: readonly string[]) {
  const actual = Object.keys(value);
  return actual.length === expected.length && actual.every(key => expected.includes(key));
}
function boundedString(value: unknown): value is string { return typeof value === "string" && value.length <= 8 * 1024 * 1024; }

/** Inspect only Zotero's standard preference carriers; keep the vendor string exact. */
function assertSupportedDocumentData(value: string) {
  const assertNoteType = (noteType: unknown) => {
    if (noteType !== 0 && !(typeof noteType === "string" && noteType.trim() !== "" && Number(noteType) === 0)) {
      throw new Error(unsupportedNoteCitationStyleMessage);
    }
  };
  let json: unknown;
  try {json = JSON.parse(value);} catch { /* Unknown opaque vendor data is retained. */ }
  if (json && typeof json === "object" && !Array.isArray(json)) {
    const prefs = (json as Record<string, unknown>).prefs;
    if (prefs && typeof prefs === "object" && !Array.isArray(prefs) && Object.hasOwn(prefs, "noteType")) {
      assertNoteType((prefs as Record<string, unknown>).noteType);
    }
    return;
  }
  const trimmed = value.trimStart();
  if (!trimmed.startsWith("<")) return;
  const looksStandard = /<data(?=[\s/>])/u.test(trimmed);
  if (/<!DOCTYPE\b/iu.test(trimmed)) {
    if (looksStandard) throw new Error("Zotero document preferences are invalid.");
    return;
  }
  const document = new DOMParser().parseFromString(value, "application/xml");
  const root = document.documentElement;
  const parserError = document.getElementsByTagName("parsererror").length > 0;
  if ((looksStandard || root?.localName === "data") && parserError) throw new Error("Zotero document preferences are invalid.");
  if (root?.localName !== "data") return;
  for (const prefs of Array.from(root.children).filter(element => element.localName === "prefs")) {
    for (const pref of Array.from(prefs.children).filter(element => element.localName === "pref" && element.getAttribute("name") === "noteType")) {
      assertNoteType(pref.getAttribute("value"));
    }
  }
}

/** The native bridge decodes a closed callback schema, before source planning. */
export function validZoteroCallback(value: unknown): value is ZoteroCallback {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const object = value as Record<string, unknown>;
  switch (object.type) {
  case "canInsertField": case "getDocumentData": case "cursorInField": case "insertField": case "getFields":
    return keys(object, ["type"]);
  case "setDocumentData": return keys(object, ["type", "value"]) && boundedString(object.value);
  case "deleteField": case "selectField": case "removeFieldCode": case "getFieldText":
    return keys(object, ["type", "id"]) && identifier(object.id);
  case "setFieldCode": return keys(object, ["type", "id", "code"]) && identifier(object.id) && boundedString(object.code);
  case "setFieldText": return keys(object, ["type", "id", "html"]) && identifier(object.id) && boundedString(object.html);
  case "setBibliographyStyle": {
    if (!keys(object, ["type", "style"]) || !object.style || typeof object.style !== "object" || Array.isArray(object.style)) return false;
    const style = object.style as Record<string, unknown>;
    return keys(style, ["firstLineIndent", "indent", "lineSpacing", "entrySpacing", "tabStops"])
      && [style.firstLineIndent, style.indent, style.lineSpacing, style.entrySpacing].every(n => typeof n === "number" && Number.isFinite(n) && Math.abs(n) <= 1_000_000)
      && typeof style.lineSpacing === "number" && style.lineSpacing > 0
      && typeof style.entrySpacing === "number" && style.entrySpacing >= 0
      && Array.isArray(style.tabStops) && style.tabStops.length <= 128
      && style.tabStops.every(n => typeof n === "number" && Number.isFinite(n) && Math.abs(n) <= 1_000_000);
  }
  default: return false;
  }
}

/** Owns one disposable candidate derived from an immutable source capture.
 * No callback changes the live EditorState or its source/history authority. */
export class ZoteroMarkdownTransaction {
  readonly originalSource: string;
  private candidate: string;
  private aggregate: ChangeSet;
  private readonly capturedSelection: {anchor: number; head: number};
  private readonly captureContext: ZoteroTransactionCapture;
  private insertionPoint: number;
  private replacement: {to: number; expected: string} | undefined;
  private cursorFieldID: string | undefined;
  private targetFieldID: string | undefined;
  private selectedFieldID: string | undefined;
  private newFieldID: string;
  private inserted = false;
  private cancelledInsertion = false;
  private targetWritten = false;
  private observedFields = false;
  private closed = false;
  private cancelled = false;

  static capture(state: EditorState, context: ZoteroTransactionCapture) {
    return new ZoteroMarkdownTransaction(state, context);
  }

  private constructor(state: EditorState, context: ZoteroTransactionCapture) {
    if (!transactionIdentifier(context.transactionID) || !commands.has(context.command) || context.composing
      || !Number.isSafeInteger(context.interactionRevision) || context.interactionRevision < 0
      || !Number.isSafeInteger(context.compositionRevision) || context.compositionRevision < 0
      || !["livePreview", "source"].includes(context.mode) || state.selection.ranges.length !== 1) throw new Error("Citation capture is unavailable.");
    this.captureContext = {...context, referenceRange: context.referenceRange ? {...context.referenceRange} : undefined};
    this.originalSource = this.candidate = state.field(exactSourceState).text;
    const projection = projectFields(this.originalSource);
    if (projection.diagnostics.length) throw new Error("Citation fields require source recovery.");
    this.aggregate = ChangeSet.empty(this.originalSource.length);
    const selection = state.selection.main;
    this.capturedSelection = {anchor: selection.anchor, head: selection.head};
    const head = exactOffsetForNormalizedOffset(this.originalSource, selection.head);
    const from = exactOffsetForNormalizedOffset(this.originalSource, selection.from);
    const to = exactOffsetForNormalizedOffset(this.originalSource, selection.to);
    if (head === null || from === null || to === null) throw new Error("Citation selection is invalid.");
    const field = projection.fields.find(field => from >= field.range.from && to <= field.range.to && head < field.range.to);
    if (!selection.empty && !field && (context.command === "addEditCitation" || context.command === "addEditBibliography")) throw new Error("Citation insertion needs one caret.");
    this.cursorFieldID = field?.id;
    this.targetFieldID = context.command === "addEditBibliography"
      ? [...projection.fields].reverse().find(field => field.kind === "bibliography")?.id : field?.id;
    this.insertionPoint = head;
    if (context.referenceRange) {
      const reference = context.referenceRange;
      const exactFrom = exactOffsetForNormalizedOffset(this.originalSource, reference.from);
      const exactTo = exactOffsetForNormalizedOffset(this.originalSource, reference.to);
      if (field || !selection.empty || exactFrom === null || exactTo === null || reference.to !== selection.head
        || reference.from >= reference.to || !/^@[^\r\n@|\]]{0,512}$/.test(reference.expected)
        || this.originalSource.slice(exactFrom, exactTo) !== reference.expected) throw new Error("Citation completion is stale.");
      this.insertionPoint = exactFrom;
      this.replacement = {to: exactTo, expected: reference.expected};
    }
    // Host occurrence identity is independent of Zotero item/citation IDs.
    this.newFieldID = "host_" + boundedUUID().replaceAll("-", "");
  }

  private current(state: EditorState, context: ZoteroTransactionContext) {
    return !this.closed && !context.composing && context.transactionID === this.captureContext.transactionID
      && context.mode === this.captureContext.mode && context.interactionRevision === this.captureContext.interactionRevision
      && context.compositionRevision === this.captureContext.compositionRevision
      && state.field(exactSourceState).text === this.originalSource && state.selection.ranges.length === 1
      && state.selection.main.anchor === this.capturedSelection.anchor && state.selection.main.head === this.capturedSelection.head;
  }

  private stage(operation: FieldOperation) {
    const planned = stageFieldOperation(projectFields(this.candidate), operation);
    const change = ChangeSet.of(planned.changes.map(range => ({from: range.from, to: range.to,
      insert: Text.of(range.insert.split("\n"))})), this.candidate.length);
    if (planned.expectedSource !== this.candidate
      || change.apply(Text.of(this.candidate.split("\n"))).toString() !== planned.source) throw new Error("Citation source plan is inconsistent.");
    this.aggregate = this.aggregate.compose(change);
    if (!this.cursorFieldID) {
      this.insertionPoint = change.mapPos(this.insertionPoint, -1);
      if (this.replacement) this.replacement = {...this.replacement, to: change.mapPos(this.replacement.to, 1)};
    }
    this.candidate = planned.source;
  }

  applyCallback(state: EditorState, context: ZoteroTransactionContext, callback: ZoteroCallback): ZoteroCallbackReply {
    try {
      if (!this.current(state, context) || !validZoteroCallback(callback)) throw new Error("Citation transaction has lost editor authority.");
      const projection = projectFields(this.candidate);
      if (projection.diagnostics.length) throw new Error("Citation fields require source recovery.");
      const field = (id: string) => {
        const value = projection.fields.find(field => field.id === id);
        if (!value) throw new Error("Citation field identity is unavailable.");
        return value;
      };
      const replyField = ({id, code, text, noteIndex, adjacent}: ProjectedField): ZoteroCallbackField => ({id, code, text, noteIndex, adjacent});
      switch (callback.type) {
      case "getDocumentData": return {kind: "string", value: projection.documentData ?? ""};
      case "setDocumentData":
        assertSupportedDocumentData(callback.value); this.stage({documentData: callback.value}); return {kind: "none"};
      case "setBibliographyStyle": this.stage({bibliographyStyle: callback.style}); return {kind: "none"};
      case "getFields": this.observedFields = true; return {kind: "fields", value: projection.fields.map(replyField)};
      case "cursorInField": {
        this.observedFields = true;
        const value = projection.fields.find(field => field.id === this.cursorFieldID);
        return {kind: "field", value: value ? replyField(value) : null};
      }
      case "canInsertField":
        if (this.cursorFieldID) return {kind: "boolean", value: true};
        try {
          stageFieldOperation(projection, {insertions: [{at: this.insertionPoint, replacement: this.replacement,
            field: {id: this.newFieldID, kind: this.captureContext.command === "addEditBibliography" ? "bibliography" : "citation", code: "", text: "{Citation}"}}]});
          return {kind: "boolean", value: true};
        } catch {return {kind: "boolean", value: false};}
      case "insertField": {
        if (this.inserted || this.cursorFieldID || !["addEditCitation", "addEditBibliography"].includes(this.captureContext.command)) throw new Error("Citation insertion is unavailable.");
        this.stage({insertions: [{at: this.insertionPoint, replacement: this.replacement,
          field: {id: this.newFieldID, kind: this.captureContext.command === "addEditBibliography" ? "bibliography" : "citation", code: "", text: "{Citation}"}}]});
        this.inserted = true;
        this.cursorFieldID = this.targetFieldID = this.newFieldID;
        this.replacement = undefined;
        return {kind: "field", value: replyField(projectFields(this.candidate).fields.find(field => field.id === this.newFieldID)!)};
      }
      case "getFieldText": return {kind: "string", value: field(callback.id).text};
      case "setFieldText":
        field(callback.id); this.stage({updates: [{id: callback.id, text: callback.html}]});
        if (callback.id === this.targetFieldID) this.targetWritten = true;
        return {kind: "none"};
      case "setFieldCode":
        field(callback.id); this.stage({updates: [{id: callback.id, code: callback.code}]});
        if (this.captureContext.command === "addEditBibliography" && !this.targetFieldID
          && projectFields(this.candidate).fields.find(field => field.id === callback.id)?.kind === "bibliography") this.targetFieldID = callback.id;
        if (callback.id === this.targetFieldID) this.targetWritten = true;
        return {kind: "none"};
      case "deleteField": case "removeFieldCode": {
        const removed = field(callback.id);
        // Zotero deletes the new TEMP occurrence when its citation picker is canceled.
        // The captured query remains authoritative until an accepted final command.
        if (callback.type === "deleteField" && this.inserted && callback.id === this.newFieldID && !isCompletedFieldCode(removed)) this.cancelledInsertion = true;
        this.stage({updates: [{id: callback.id, ...(callback.type === "deleteField" ? {delete: true} : {unlink: true})}]});
        if (this.cursorFieldID === callback.id) this.cursorFieldID = undefined;
        if (this.selectedFieldID === callback.id) this.selectedFieldID = undefined;
        return {kind: "none"};
      }
      case "selectField":
        field(callback.id); this.selectedFieldID = this.cursorFieldID = callback.id;
        return {kind: "selection", fieldID: callback.id};
      }
    } catch (error) {this.closed = true; throw error;}
  }

  finalize(state: EditorState, context: ZoteroTransactionContext, remote: ZoteroRemoteCompletion): FinalizedZoteroOperation | null {
    try {
      if (this.cancelled || remote.status === "cancelled") return null;
      if (!this.current(state, context)) throw new Error("Citation transaction has lost editor authority.");
      if (remote.status !== "cleanedUp" || remote.remoteCleanupConfirmed !== true) throw new Error("Zotero cleanup was not confirmed.");
      if (this.cancelledInsertion) return null;
      if (this.candidate === this.originalSource && !this.targetWritten
        && (this.captureContext.command !== "refresh" || !this.observedFields)) return null;
      const projection = projectFields(this.candidate);
      if (projection.diagnostics.length || !projection.documentData?.trim() || projection.fields.some(field => !isCompletedFieldCode(field)
        || !field.text.trim() || ["{Citation}", "{Bibliography}"].includes(field.text.trim()))) throw new Error("Citation command left incomplete source state.");
      if (this.captureContext.command === "addEditCitation" || this.captureContext.command === "addEditBibliography") {
        const target = projection.fields.find(field => field.id === this.targetFieldID);
        const expectedKind = this.captureContext.command === "addEditCitation" ? "citation" : "bibliography";
        if (!target || target.kind !== expectedKind || !this.targetWritten) throw new Error("Citation command did not complete the requested field.");
      } else if (this.captureContext.command === "refresh" && !this.observedFields) throw new Error("Citation refresh did not verify document fields.");
      else if (this.captureContext.command === "setDocPrefs" && this.candidate === this.originalSource) return null;
      this.stage({acceptCurrentFields: true});
      const accepted = projectFields(this.candidate);
      if (accepted.diagnostics.length || accepted.citationStateStale) throw new Error("Citation acceptance does not match source fields.");
      if (this.candidate === this.originalSource) return null;
      const changes: SourceReplacement[] = [];
      this.aggregate.iterChanges((from, to, _newFrom, _newTo, text) => {
        changes.push({from, to, expected: this.originalSource.slice(from, to), insert: text.toString()});
      });
      const target = accepted.fields.find(field => field.id === (this.selectedFieldID ?? this.targetFieldID));
      const cursor = target ? normalizedDocumentText(this.candidate.slice(0, target.range.to)).length : undefined;
      return {expectedSource: this.originalSource, source: this.candidate, changes,
        ...(cursor === undefined ? {} : {selection: {anchor: cursor, head: cursor}})};
    } finally {this.closed = true;}
  }

  cancel() {this.cancelled = true; this.closed = true; this.candidate = this.originalSource;}
}

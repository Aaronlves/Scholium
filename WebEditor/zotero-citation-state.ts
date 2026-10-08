import {StateEffect, StateField, type Extension} from "@codemirror/state";
import {invertedEffects} from "@codemirror/commands";
import {maximumFallbackLength, maximumFields, validBibliographyStyle, validFieldID,
  type BibliographyStyle, type FieldInput, type FieldSignature} from "./zotero-field-envelope";

export interface ZoteroCitationData {
  schemaVersion: 1;
  fields: readonly FieldInput[];
  documentData?: string;
  bibliographyStyle?: BibliographyStyle;
  acceptedFields?: readonly FieldSignature[];
}
export interface CitationFingerprint {sha256: string; byteCount: number}
export interface ZoteroCitationSnapshot {
  noteID: string;
  vaultID: string;
  revision?: CitationFingerprint;
  sourceFingerprint?: CitationFingerprint;
  data?: ZoteroCitationData;
  status: "absent" | "available" | "unresolved" | "unsupported";
}
export const maximumCitationDataBytes = 8 * 1024 * 1024;
const maximumOpaqueLength = 256 * 1024;
const bounded = (value: unknown, maximum: number): value is string => typeof value === "string"
  && value.length <= maximum && !/[\ud800-\udfff]/u.test(value);
const only = (value: object, allowed: readonly string[]) => Object.keys(value).every(key => allowed.includes(key));
export function validCitationData(value: unknown): value is ZoteroCitationData {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const data = value as ZoteroCitationData;
  return data.schemaVersion === 1 && only(data, ["schemaVersion", "fields", "documentData", "bibliographyStyle", "acceptedFields"])
    && Array.isArray(data.fields) && data.fields.length <= maximumFields
    && data.fields.every(field => field && validFieldID(field.id) && ["citation", "bibliography"].includes(field.kind)
      && only(field, ["id", "kind", "code", "text"]) && bounded(field.code, maximumOpaqueLength) && bounded(field.text, maximumFallbackLength))
    && new Set(data.fields.map(field => field.id)).size === data.fields.length
    && (data.documentData === undefined || bounded(data.documentData, maximumOpaqueLength))
    && (data.bibliographyStyle === undefined || validBibliographyStyle(data.bibliographyStyle))
    && (data.acceptedFields === undefined || Array.isArray(data.acceptedFields) && data.acceptedFields.length <= maximumFields
      && data.acceptedFields.every(field => field && only(field, ["id", "code"]) && validFieldID(field.id) && bounded(field.code, maximumOpaqueLength))
      && new Set(data.acceptedFields.map(field => field.id)).size === data.acceptedFields.length)
    && new TextEncoder().encode(JSON.stringify(data)).byteLength <= maximumCitationDataBytes;
}
export function validCitationSnapshot(value: unknown): value is ZoteroCitationSnapshot {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const snapshot = value as ZoteroCitationSnapshot;
  const uuid = (id: unknown) => typeof id === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
  const fingerprint = (value: CitationFingerprint | undefined) => value === undefined || value && only(value, ["sha256", "byteCount"])
    && /^[0-9a-f]{64}$/.test(value.sha256) && Number.isSafeInteger(value.byteCount) && value.byteCount >= 0;
  return only(snapshot, ["noteID", "vaultID", "revision", "sourceFingerprint", "data", "status"])
    && uuid(snapshot.noteID) && uuid(snapshot.vaultID) && fingerprint(snapshot.revision) && fingerprint(snapshot.sourceFingerprint)
    && ["absent", "available", "unresolved", "unsupported"].includes(snapshot.status)
    && (snapshot.data === undefined || validCitationData(snapshot.data))
    && (snapshot.status !== "available" || snapshot.data !== undefined && snapshot.sourceFingerprint !== undefined)
    && (snapshot.status !== "absent" || snapshot.data === undefined && snapshot.revision === undefined);
}
export function citationDataEqual(left: ZoteroCitationData | undefined, right: ZoteroCitationData | undefined) {
  // Dictionary key order is not part of the vendor contract; vendor string bytes are.
  if (left === right) return true;
  if (!left || !right) return false;
  return JSON.stringify([left.schemaVersion, left.fields.map(f => [f.id, f.kind, f.code, f.text]), left.documentData,
    left.bibliographyStyle && [left.bibliographyStyle.firstLineIndent, left.bibliographyStyle.indent,
      left.bibliographyStyle.lineSpacing, left.bibliographyStyle.entrySpacing, left.bibliographyStyle.tabStops],
    left.acceptedFields?.map(f => [f.id, f.code])]) === JSON.stringify([right.schemaVersion,
    right.fields.map(f => [f.id, f.kind, f.code, f.text]), right.documentData,
    right.bibliographyStyle && [right.bibliographyStyle.firstLineIndent, right.bibliographyStyle.indent,
      right.bibliographyStyle.lineSpacing, right.bibliographyStyle.entrySpacing, right.bibliographyStyle.tabStops],
    right.acceptedFields?.map(f => [f.id, f.code])]);
}

export function citationSnapshotEqual(left: ZoteroCitationSnapshot | undefined, right: ZoteroCitationSnapshot | undefined) {
  if (left === right) return true;
  if (!left || !right) return false;
  return left.noteID === right.noteID && left.vaultID === right.vaultID && left.status === right.status
    && left.revision?.sha256 === right.revision?.sha256 && left.revision?.byteCount === right.revision?.byteCount
    && left.sourceFingerprint?.sha256 === right.sourceFingerprint?.sha256 && left.sourceFingerprint?.byteCount === right.sourceFingerprint?.byteCount
    && citationDataEqual(left.data, right.data);
}

/** Disk CAS identity never enters Undo. History owns only pending semantic data. */
export interface ZoteroCitationSession {baseline: ZoteroCitationSnapshot; data?: ZoteroCitationData}
export const setCitationSnapshot = StateEffect.define<ZoteroCitationSnapshot | undefined>();
export const setCitationData = StateEffect.define<ZoteroCitationData | undefined>();
export const citationState = StateField.define<ZoteroCitationSession | undefined>({
  create: () => undefined,
  update(value, transaction) {
    for (const effect of transaction.effects) {
      if (effect.is(setCitationSnapshot)) value = effect.value ? {baseline: effect.value, data: effect.value.data} : undefined;
      if (effect.is(setCitationData)) {
        if (!value) throw new Error("A standalone editor cannot own a citation companion.");
        value = {...value, data: effect.value};
      }
    }
    return value;
  },
  toJSON: value => value ?? null,
  fromJSON(value) {
    if (value === null) return undefined;
    if (!value || !only(value, ["baseline", "data"]) || !validCitationSnapshot(value.baseline)
      || value.data !== undefined && !validCitationData(value.data)) throw new Error("Invalid recovered citation companion.");
    return value;
  },
});
export const citationHistory: Extension = [citationState, invertedEffects.of(transaction =>
  transaction.effects.some(effect => effect.is(setCitationData))
    ? [setCitationData.of(transaction.startState.field(citationState)?.data)] : [])];

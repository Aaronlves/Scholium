/** Source carrier schema. Vendor code and rendered HTML are never interpreted here. */
export interface SourceRange {from: number; to: number}
export type FieldKind = "citation" | "bibliography";
export interface FieldInput {id: string; kind: FieldKind; code: string; text: string}
export interface BibliographyStyle {
  firstLineIndent: number;
  indent: number;
  lineSpacing: number;
  entrySpacing: number;
  tabStops: readonly number[];
}
export interface FieldSignature {id: string; code: string}
export interface DocumentEnvelope {
  data: string;
  bibliographyStyle?: BibliographyStyle;
  acceptedFields?: readonly FieldSignature[];
}
export const citationDestinationPrefix = "scholium-zotero:";
export const bibliographyPrefix = "<!--scholium-zotero-field:";
export const bibliographyClose = "<!--/scholium-zotero-field-->";
export const documentPrefix = "<!--scholium-zotero-document:";
export const maximumEnvelopeLength = 256 * 1024;
export const maximumFallbackLength = 64 * 1024;
export const maximumFields = 1024;

export function encodeOpaque(value: string) {
  if (/[\ud800-\udfff]/u.test(value)) throw new Error("Opaque state contains a lone surrogate.");
  const bytes = new TextEncoder().encode(value);
  const payload = btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(""));
  if (payload.length > maximumEnvelopeLength) throw new Error("The citation state exceeds the supported source envelope size.");
  return payload;
}
export function decodeOpaque(value: string) {
  if (value.length > maximumEnvelopeLength || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    throw new Error("Invalid bounded base64 payload.");
  }
  const decoded = new TextDecoder("utf-8", {fatal: true}).decode(Uint8Array.from(atob(value), char => char.charCodeAt(0)));
  if (encodeOpaque(decoded) !== value) throw new Error("Noncanonical encoded payload.");
  return decoded;
}
export function validFieldID(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_-]{0,127}$/.test(value);
}
export function decodeFieldPayload(payload: string, kind: FieldKind): FieldInput {
  const field = JSON.parse(decodeOpaque(payload)) as Record<string, unknown>;
  if (!field || !validFieldID(field.id) || field.kind !== kind
    || typeof field.code !== "string" || typeof field.text !== "string"
    || Object.keys(field).some(key => !["id", "kind", "code", "text"].includes(key))) {
    throw new Error("Invalid or unsupported host field identity or payload.");
  }
  return {id: field.id, kind, code: field.code, text: field.text};
}
export function fieldPayload(field: FieldInput) {
  if (!validFieldID(field.id) || !["citation", "bibliography"].includes(field.kind)
    || typeof field.code !== "string" || typeof field.text !== "string") throw new Error("Invalid host field identity or payload.");
  return encodeOpaque(JSON.stringify({id: field.id, kind: field.kind, code: field.code, text: field.text}));
}
export function isCitationDestination(destination: string) {
  return /^scholium-zotero:/i.test(destination);
}

/** Called only for a Link range proved by the existing Markdown parser. */
export function citationLinkSource(raw: string): {field: FieldInput; fallbackRange: SourceRange} | null {
  const boundary = raw.lastIndexOf("](");
  if (!raw.startsWith("[") || boundary < 1 || !raw.endsWith(")")) return null;
  const destination = raw.slice(boundary + 2, -1);
  if (!isCitationDestination(destination)) return null;
  if (!destination.startsWith(`${citationDestinationPrefix}1:`)) throw new Error("Unknown citation source envelope version.");
  const field = decodeFieldPayload(destination.slice(`${citationDestinationPrefix}1:`.length), "citation");
  const fallbackRange = {from: 1, to: boundary};
  if (fallbackRange.to - fallbackRange.from > maximumFallbackLength || /[\r\n]/.test(raw.slice(1, boundary))) {
    throw new Error("Citation fallback must be bounded inline Markdown.");
  }
  return {field, fallbackRange};
}
export function validBibliographyStyle(value: unknown): value is BibliographyStyle {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const style = value as Record<string, unknown>;
  return Object.keys(style).sort().join(",") === "entrySpacing,firstLineIndent,indent,lineSpacing,tabStops"
    && [style.firstLineIndent, style.indent, style.lineSpacing, style.entrySpacing]
      .every(value => typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= 100000)
    && (style.lineSpacing as number) > 0 && (style.entrySpacing as number) >= 0
    && Array.isArray(style.tabStops) && style.tabStops.length <= 64
    && style.tabStops.every(value => typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= 100000);
}
function validSignatures(value: unknown): value is readonly FieldSignature[] {
  return Array.isArray(value) && value.length <= maximumFields
    && value.every(field => field && validFieldID(field.id) && typeof field.code === "string"
      && Object.keys(field).sort().join(",") === "code,id")
    && new Set(value.map(field => field.id)).size === value.length;
}
export function decodeDocumentPayload(payload: string): DocumentEnvelope {
  const value = JSON.parse(decodeOpaque(payload)) as Record<string, unknown>;
  if (!value || typeof value.data !== "string"
    || Object.keys(value).some(key => !["data", "bibliographyStyle", "acceptedFields"].includes(key))
    || (value.bibliographyStyle !== undefined && !validBibliographyStyle(value.bibliographyStyle))
    || (value.acceptedFields !== undefined && !validSignatures(value.acceptedFields))) throw new Error("Invalid document source envelope.");
  return value as unknown as DocumentEnvelope;
}
export function encodeDocumentData(data: string, bibliographyStyle: BibliographyStyle | null = null,
  acceptedFields: readonly FieldSignature[] | null = null) {
  if (typeof data !== "string" || (bibliographyStyle !== null && !validBibliographyStyle(bibliographyStyle))
    || (acceptedFields !== null && !validSignatures(acceptedFields))) throw new Error("Invalid document source envelope.");
  return `${documentPrefix}1:${encodeOpaque(JSON.stringify({data,
    ...(bibliographyStyle ? {bibliographyStyle} : {}), ...(acceptedFields ? {acceptedFields} : {})}))}-->`;
}

/** Completion admission only; vendor strings remain exact and opaque in source. */
export function isCompletedFieldCode(field: Pick<FieldInput, "kind" | "code">) {
  const prefix = field.kind === "citation" ? "ITEM CSL_CITATION " : "BIBL ";
  if (!field.code.startsWith(prefix)) return false;
  try {
    const body = field.code.slice(prefix.length);
    if (field.kind === "bibliography" && !body.endsWith(" CSL_BIBLIOGRAPHY")) return false;
    const json = field.kind === "bibliography" ? body.slice(0, -" CSL_BIBLIOGRAPHY".length) : body;
    const value = JSON.parse(json) as Record<string, unknown>;
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    if (field.kind === "bibliography") return true;
    return Array.isArray(value.citationItems) && value.citationItems.length > 0
      && value.citationItems.every(item => item && typeof item === "object" && !Array.isArray(item)
        && ((typeof item.id === "string" && item.id.length > 0)
          || (typeof item.id === "number" && Number.isSafeInteger(item.id) && item.id > 0)));
  } catch { return false; }
}

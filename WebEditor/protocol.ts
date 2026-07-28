export const EDITOR_PROTOCOL_VERSION = 7;
export const MAX_INBOUND_BYTES = 2_500_000;
export const MAX_SOURCE_UTF8_BYTES = 8_000_000;

export type EditorMode = "livePreview" | "source";
export type MarkdownEditorCommand =
  | "bold" | "emphasis" | "strikethrough" | "highlight" | "inlineCode"
  | "standardLink" | "wikilink" | "vectorSupports"
  | "vectorOpposes" | "vectorIncompatible"
  | "paragraph" | "heading1" | "heading2" | "heading3" | "heading4"
  | "heading5" | "heading6" | "blockQuotation" | "bulletList"
  | "numberedList" | "taskList" | "fencedCode" | "thematicBreak"
  | "calloutOrient" | "calloutCite" | "calloutConnect" | "calloutState"
  | "calloutIllustrate" | "calloutQuote" | "calloutFlag"
  | "insertFootnote" | "insertTable" | "toggleTask"
  | "tableInsertRowBefore" | "tableInsertRowAfter" | "tableDeleteRow"
  | "tableInsertColumnBefore" | "tableInsertColumnAfter" | "tableDeleteColumn"
  | "tableAlignLeft" | "tableAlignCenter" | "tableAlignRight"
  | "pastePlain" | "pasteMarkdown" | "linkSelectedText";

export interface SelectionRange { anchor: number; head: number }
export interface SelectionSnapshot {
  documentID: string;
  fingerprint: string;
  generation: number;
  ranges: SelectionRange[];
}
export interface RecoverySnapshot extends SelectionSnapshot {
  source: string;
  stateJSON?: string;
  undoHistoryPreserved: boolean;
  dirty: boolean;
}
export interface EditorScrollAnchor {
  sourceUTF16Offset: number;
  blockUTF16LowerBound: number;
  blockUTF16UpperBound: number;
  relativeBlockPosition: number;
  fallbackFraction: number;
}
export interface MarkdownEditingDialect {
  version: number;
  callouts: Array<{identifier: string; aliases: string[]; label: string; meaning: string}>;
  vectorLinkOperators: Array<{
    marker: string;
    kind: "neutral" | "supports" | "opposes" | "incompatible";
    meaning: string;
  }>;
  footnotes: {
    namedReferenceOpening: string;
    namedReferenceClosing: string;
    definitionSeparator: string;
    inlineOpening: string;
    continuationIndentSpaces: number;
    allowsTabContinuation: boolean;
    caseSensitiveIdentifiers: boolean;
    ordinalByFirstReference: boolean;
  };
  mathematics: {
    inlineDelimiter: string;
    displayDelimiter: string;
    singleDollarInline: boolean;
  };
}
export interface EditorContext {
  selections: SelectionRange[];
  activeInlineConstructs: string[];
  activeBlockConstructs: string[];
  tablePosition?: {row: number; column: number; rowCount: number; columnCount: number};
  composing: boolean;
  availableCommands: MarkdownEditorCommand[];
  undoLabel?: string;
  redoLabel?: string;
}
export interface EditorPerformanceSample {
  name: string;
  durationMilliseconds: number;
  observed: Record<string, number>;
}
export type EditorOperation =
  | {type: "initialize"; text: string; mode: EditorMode; dialect: MarkdownEditingDialect}
  | {type: "setMode"; mode: EditorMode}
  | {type: "setPresentationCSS"; value: string}
  | {type: "setUserCSS"; value: string}
  | {type: "setLinkPreviews"; value: unknown[]}
  | {type: "showPreview"}
  | {type: "showPreviewAt"; x: number; y: number}
  | {type: "announceStatus"; value: string}
  | {type: "goToLine"; line: number}
  | {type: "revealSourceRange"; fromUTF16: number; toUTF16: number}
  | {type: "setScrollFraction"; fraction: number}
  | {type: "setScrollAnchor"; anchor: EditorScrollAnchor}
  | {type: "queryText"} | {type: "querySelection"} | {type: "queryContext"} | {type: "queryScrollAnchor"}
  | {type: "queryPerformance"}
  | {type: "captureRecovery"}
  | {type: "restoreRecovery"; snapshot: RecoverySnapshot}
  | {type: "synchronizeCommittedText"; expectedText: string; committedText: string; committedFingerprint: string}
  | {type: "command"; command: MarkdownEditorCommand; argument?: string}
  | {type: "markClean"} | {type: "focus"} | {type: "blur"};
export interface EditorRequest {
  protocolVersion: number;
  requestID: string;
  sessionID: string;
  documentID: string;
  startingFingerprint: string;
  expectedGeneration: number;
  operation: EditorOperation;
}
export interface EditorCommandResult {
  requestID: string;
  resultingGeneration: number;
  sourceChanged: boolean;
  selections: SelectionRange[];
  undoLabel?: string;
  text?: string;
  context?: EditorContext;
  selection?: SelectionSnapshot;
  recovery?: RecoverySnapshot;
  scrollAnchor?: EditorScrollAnchor;
  performanceSamples?: EditorPerformanceSample[];
  accepted: boolean;
  error?: string;
}

const operationTypes = new Set([
  "initialize", "setMode", "setPresentationCSS", "setUserCSS", "setLinkPreviews", "showPreview", "showPreviewAt", "announceStatus",
  "goToLine", "revealSourceRange", "setScrollFraction", "setScrollAnchor", "queryText", "querySelection", "queryContext", "queryScrollAnchor", "queryPerformance",
  "captureRecovery", "restoreRecovery", "synchronizeCommittedText", "command", "markClean", "focus", "blur",
]);
const commandTypes = new Set<MarkdownEditorCommand>([
  "bold", "emphasis", "strikethrough", "highlight", "inlineCode", "standardLink", "wikilink",
  "vectorSupports", "vectorOpposes", "vectorIncompatible", "paragraph", "heading1",
  "heading2", "heading3", "heading4", "heading5", "heading6", "blockQuotation", "bulletList",
  "numberedList", "taskList", "fencedCode", "thematicBreak", "calloutOrient", "calloutCite",
  "calloutConnect", "calloutState", "calloutIllustrate", "calloutQuote", "calloutFlag",
  "insertFootnote", "insertTable", "toggleTask", "tableInsertRowBefore", "tableInsertRowAfter",
  "tableDeleteRow", "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
  "tableAlignLeft", "tableAlignCenter", "tableAlignRight", "pastePlain", "pasteMarkdown",
  "linkSelectedText",
]);
function validMode(value: unknown): value is EditorMode {
  return value === "livePreview" || value === "source";
}
function validRecoverySnapshot(value: unknown): value is RecoverySnapshot {
  if (!value || typeof value !== "object") return false;
  const snapshot = value as Partial<RecoverySnapshot>;
  if (typeof snapshot.documentID !== "string" || snapshot.documentID.length > 4_096
      || typeof snapshot.fingerprint !== "string" || snapshot.fingerprint.length > 256
      || !Number.isSafeInteger(snapshot.generation) || snapshot.generation! < 0
      || typeof snapshot.source !== "string"
      || typeof snapshot.undoHistoryPreserved !== "boolean"
      || typeof snapshot.dirty !== "boolean"
      || !Array.isArray(snapshot.ranges) || snapshot.ranges.length === 0
      || snapshot.ranges.length > 256
      || (snapshot.stateJSON !== undefined && typeof snapshot.stateJSON !== "string")) return false;
  const normalizedLength = snapshot.source.replaceAll("\r\n", "\n").length;
  return snapshot.ranges.every((range) => Boolean(range)
    && Number.isSafeInteger(range.anchor) && range.anchor >= 0 && range.anchor <= normalizedLength
    && Number.isSafeInteger(range.head) && range.head >= 0 && range.head <= normalizedLength);
}

/** A recovery snapshot may advance, but never rewind, source authority. */
export function recoveryGenerationCanReplaceCurrent(
  snapshotGeneration: number,
  currentGeneration: number,
) {
  return Number.isSafeInteger(snapshotGeneration)
    && Number.isSafeInteger(currentGeneration)
    && snapshotGeneration >= currentGeneration;
}
function validDialect(value: unknown): value is MarkdownEditingDialect {
  if (!value || typeof value !== "object") return false;
  const dialect = value as Partial<MarkdownEditingDialect>;
  const callouts = dialect.callouts;
  const vectors = dialect.vectorLinkOperators;
  const footnotes = dialect.footnotes;
  const mathematics = dialect.mathematics;
  return dialect.version === 4
    && Array.isArray(callouts) && callouts.length > 0 && callouts.length <= 32
    && callouts.every((callout) => Boolean(callout)
      && typeof callout.identifier === "string" && callout.identifier.length <= 64
      && Array.isArray(callout.aliases) && callout.aliases.length <= 32
      && callout.aliases.every((alias) => typeof alias === "string" && alias.length <= 64)
      && typeof callout.label === "string" && callout.label.length <= 120
      && typeof callout.meaning === "string" && callout.meaning.length <= 1_000)
    && Array.isArray(vectors) && vectors.length === 4
    && vectors.every((vector) => Boolean(vector)
      && ["", "+", "-", "?"].includes(vector.marker)
      && ["neutral", "supports", "opposes", "incompatible"].includes(vector.kind)
      && typeof vector.meaning === "string" && vector.meaning.length <= 1_000)
    && Boolean(footnotes)
    && footnotes?.namedReferenceOpening === "[^"
    && footnotes.namedReferenceClosing === "]"
    && footnotes.definitionSeparator === ":"
    && footnotes.inlineOpening === "^["
    && footnotes.continuationIndentSpaces === 2
    && footnotes.allowsTabContinuation === true
    && footnotes.caseSensitiveIdentifiers === true
    && footnotes.ordinalByFirstReference === true
    && Boolean(mathematics)
    && mathematics?.inlineDelimiter === "$"
    && mathematics.displayDelimiter === "$$"
    && mathematics.singleDollarInline === true;
}
function validOperation(operation: Record<string, unknown>) {
  switch (operation.type) {
  case "initialize":
    return typeof operation.text === "string" && validMode(operation.mode)
      && validDialect(operation.dialect);
  case "setMode": return validMode(operation.mode);
  case "setPresentationCSS":
  case "setUserCSS": return typeof operation.value === "string" && operation.value.length <= 1_000_000;
  case "announceStatus": return typeof operation.value === "string" && operation.value.length <= 500;
  case "setLinkPreviews": return Array.isArray(operation.value);
  case "showPreviewAt":
    return typeof operation.x === "number" && Number.isFinite(operation.x)
      && typeof operation.y === "number" && Number.isFinite(operation.y);
  case "goToLine": return Number.isSafeInteger(operation.line) && Number(operation.line) >= 1;
  case "revealSourceRange":
    return Number.isSafeInteger(operation.fromUTF16)
      && Number.isSafeInteger(operation.toUTF16)
      && Number(operation.fromUTF16) >= 0
      && Number(operation.toUTF16) >= Number(operation.fromUTF16);
  case "setScrollFraction": return typeof operation.fraction === "number" && Number.isFinite(operation.fraction);
  case "setScrollAnchor": {
    const anchor = operation.anchor as Partial<EditorScrollAnchor> | undefined;
    return Boolean(anchor)
      && Number.isSafeInteger(anchor?.sourceUTF16Offset)
      && Number.isSafeInteger(anchor?.blockUTF16LowerBound)
      && Number.isSafeInteger(anchor?.blockUTF16UpperBound)
      && typeof anchor?.relativeBlockPosition === "number"
      && Number.isFinite(anchor.relativeBlockPosition)
      && anchor.relativeBlockPosition >= 0 && anchor.relativeBlockPosition <= 1
      && typeof anchor?.fallbackFraction === "number"
      && Number.isFinite(anchor.fallbackFraction)
      && anchor.fallbackFraction >= 0 && anchor.fallbackFraction <= 1;
  }
  case "restoreRecovery": return validRecoverySnapshot(operation.snapshot);
  case "synchronizeCommittedText":
    return typeof operation.expectedText === "string" && typeof operation.committedText === "string"
      && typeof operation.committedFingerprint === "string";
  case "command":
    return typeof operation.command === "string" && commandTypes.has(operation.command as MarkdownEditorCommand)
      && (operation.argument === undefined || typeof operation.argument === "string");
  case "queryText": case "querySelection": case "queryContext": case "queryScrollAnchor": case "queryPerformance": case "captureRecovery": case "showPreview":
  case "markClean": case "focus": case "blur": return true;
  default: return false;
  }
}
export function encodedByteLength(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}
export function isEditorRequest(value: unknown): value is EditorRequest {
  if (!value || typeof value !== "object") return false;
  const request = value as Partial<EditorRequest>;
  if (request.protocolVersion !== EDITOR_PROTOCOL_VERSION
      || typeof request.requestID !== "string" || request.requestID.length > 128
      || typeof request.sessionID !== "string" || request.sessionID.length > 128
      || typeof request.documentID !== "string" || request.documentID.length > 4096
      || typeof request.startingFingerprint !== "string" || request.startingFingerprint.length > 256
      || !Number.isSafeInteger(request.expectedGeneration) || request.expectedGeneration! < 0
      || !request.operation || typeof request.operation !== "object") return false;
  const type = (request.operation as {type?: unknown}).type;
  if (typeof type !== "string" || !operationTypes.has(type)) return false;
  if (!validOperation(request.operation as unknown as Record<string, unknown>)) return false;
  try {
    const sourceBearing = ["initialize", "synchronizeCommittedText", "restoreRecovery"].includes(type);
    return encodedByteLength(value) <= (sourceBearing ? MAX_SOURCE_UTF8_BYTES + 512_000 : MAX_INBOUND_BYTES);
  } catch { return false; }
}
export function rejected(requestID: string, generation: number, error: string): EditorCommandResult {
  return {requestID, resultingGeneration: generation, sourceChanged: false, selections: [], accepted: false, error};
}

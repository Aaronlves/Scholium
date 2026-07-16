export const EDITOR_PROTOCOL_VERSION = 2;
export const MAX_INBOUND_BYTES = 2_500_000;
export const MAX_SOURCE_UTF8_BYTES = 8_000_000;

export type EditorMode = "livePreview" | "source";
export type MarkdownEditorCommand =
  | "bold" | "emphasis" | "strikethrough" | "highlight" | "inlineCode"
  | "standardLink" | "wikilink" | "vectorSupportsTarget"
  | "vectorSupportedByTarget" | "vectorIncompatible"
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
export interface MarkdownEditingDialect {
  version: number;
  callouts: Array<{identifier: string; aliases: string[]; label: string; meaning: string}>;
  vectorLinkOperators: Array<{
    marker: string;
    kind: "neutral" | "supports_target" | "supported_by_target" | "incompatible";
    meaning: string;
  }>;
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
export type EditorOperation =
  | {type: "initialize"; text: string; mode: EditorMode; dialect: MarkdownEditingDialect}
  | {type: "setMode"; mode: EditorMode}
  | {type: "setUserCSS"; value: string}
  | {type: "setLinkCompletions"; value: unknown[]}
  | {type: "setResearcherComments"; value: unknown[]}
  | {type: "announceStatus"; value: string}
  | {type: "goToLine"; line: number}
  | {type: "setScrollFraction"; fraction: number}
  | {type: "queryText"} | {type: "querySelection"} | {type: "queryContext"}
  | {type: "captureRecovery"}
  | {type: "restoreRecovery"; snapshot: RecoverySnapshot}
  | {type: "synchronizeCommittedText"; expectedText: string; committedText: string; committedFingerprint: string}
  | {type: "command"; command: MarkdownEditorCommand; argument?: string}
  | {type: "markClean"} | {type: "focus"};
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
  accepted: boolean;
  error?: string;
}

const operationTypes = new Set([
  "initialize", "setMode", "setUserCSS", "setLinkCompletions", "setResearcherComments", "announceStatus",
  "goToLine", "setScrollFraction", "queryText", "querySelection", "queryContext",
  "captureRecovery", "restoreRecovery", "synchronizeCommittedText", "command", "markClean", "focus",
]);
const commandTypes = new Set<MarkdownEditorCommand>([
  "bold", "emphasis", "strikethrough", "highlight", "inlineCode", "standardLink", "wikilink",
  "vectorSupportsTarget", "vectorSupportedByTarget", "vectorIncompatible", "paragraph", "heading1",
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
function validOperation(operation: Record<string, unknown>) {
  switch (operation.type) {
  case "initialize":
    return typeof operation.text === "string" && validMode(operation.mode)
      && Boolean(operation.dialect) && typeof operation.dialect === "object";
  case "setMode": return validMode(operation.mode);
  case "setUserCSS": return typeof operation.value === "string" && operation.value.length <= 1_000_000;
  case "announceStatus": return typeof operation.value === "string" && operation.value.length <= 500;
  case "setLinkCompletions": case "setResearcherComments": return Array.isArray(operation.value);
  case "goToLine": return Number.isSafeInteger(operation.line) && Number(operation.line) >= 1;
  case "setScrollFraction": return typeof operation.fraction === "number" && Number.isFinite(operation.fraction);
  case "restoreRecovery": return Boolean(operation.snapshot) && typeof operation.snapshot === "object";
  case "synchronizeCommittedText":
    return typeof operation.expectedText === "string" && typeof operation.committedText === "string"
      && typeof operation.committedFingerprint === "string";
  case "command":
    return typeof operation.command === "string" && commandTypes.has(operation.command as MarkdownEditorCommand)
      && (operation.argument === undefined || typeof operation.argument === "string");
  case "queryText": case "querySelection": case "queryContext": case "captureRecovery":
  case "markClean": case "focus": return true;
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

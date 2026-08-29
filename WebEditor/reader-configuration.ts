export interface ReadLinkPreview {
  utf16LowerBound: number;
  utf16UpperBound: number;
  title: string;
  isEmbedded: boolean;
  relationship?: string;
  fragment?: string;
  htmlBody: string;
}

export interface ReaderLocalization {
  strings: Record<string, string>;
}

export interface ReadCommentAnchor {
  id: string;
  discussionID: string;
  statementID: string;
  startLine: number;
  endLine: number;
  commentCount: number;
}

export interface ReaderConfiguration {
  version: 1;
  documentID: string;
  fingerprint: string;
  loadGeneration: number;
  commentEnabled: boolean;
  selectionEnabled: boolean;
  testingEnabled: boolean;
  presentationCSS: string;
  userCSS: string;
  localization: ReaderLocalization;
  linkPreviews: ReadLinkPreview[];
  commentAnchors: ReadCommentAnchor[];
  vectorSymbols: Record<string, string>;
}

const commentAnchorToken = /^[A-Za-z0-9._:-]+$/;
const uuidToken = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

export function validatedReadCommentAnchors(value: unknown): ReadCommentAnchor[] | null {
  if (!Array.isArray(value) || value.length > 4_096) return null;
  const anchors: ReadCommentAnchor[] = [];
  const identifiers = new Set<string>();
  for (const candidate of value) {
    if (!candidate || typeof candidate !== "object") return null;
    const anchor = candidate as Partial<ReadCommentAnchor>;
    if (typeof anchor.id !== "string" || !anchor.id || anchor.id.length > 160
        || !commentAnchorToken.test(anchor.id)
        || typeof anchor.discussionID !== "string" || !anchor.discussionID
        || anchor.discussionID.length > 64
        || !uuidToken.test(anchor.discussionID)
        || typeof anchor.statementID !== "string" || !anchor.statementID
        || anchor.statementID.length > 64
        || !uuidToken.test(anchor.statementID)
        || !Number.isSafeInteger(anchor.startLine) || Number(anchor.startLine) < 1
        || !Number.isSafeInteger(anchor.endLine)
        || Number(anchor.endLine) < Number(anchor.startLine)
        || !Number.isSafeInteger(anchor.commentCount)
        || Number(anchor.commentCount) < 1
        || Number(anchor.commentCount) > 4_096
        || identifiers.has(anchor.id)) return null;
    identifiers.add(anchor.id);
    anchors.push(anchor as ReadCommentAnchor);
  }
  return anchors;
}

export function validatedReaderConfiguration(value: unknown): ReaderConfiguration | null {
  if (!value || typeof value !== "object") return null;
  const config = value as Partial<ReaderConfiguration>;
  if (config.version !== 1
      || typeof config.documentID !== "string" || !config.documentID
      || config.documentID.length > 4_096
      || typeof config.fingerprint !== "string" || !config.fingerprint
      || config.fingerprint.length > 256
      || !Number.isSafeInteger(config.loadGeneration) || Number(config.loadGeneration) < 0
      || typeof config.commentEnabled !== "boolean"
      || typeof config.selectionEnabled !== "boolean"
      || typeof config.testingEnabled !== "boolean"
      || typeof config.presentationCSS !== "string"
      || typeof config.userCSS !== "string"
      || !config.localization || typeof config.localization !== "object"
      || !config.localization.strings || typeof config.localization.strings !== "object"
      || !Array.isArray(config.linkPreviews) || config.linkPreviews.length > 128
      || validatedReadCommentAnchors(config.commentAnchors) === null
      || !config.vectorSymbols || typeof config.vectorSymbols !== "object") return null;
  return config as ReaderConfiguration;
}

export interface ReadLinkPreview {
  utf16LowerBound: number;
  utf16UpperBound: number;
  title: string;
  isEmbedded: boolean;
  fragment?: string;
  htmlBody: string;
}

export interface ReaderLocalization {
  strings: Record<string, string>;
}


export interface ReaderConfiguration {
  version: 6;
  documentID: string;
  fingerprint: string;
  loadGeneration: number;
  selectionEnabled: boolean;
  chatReply?: boolean;
  chatReplyPreviousHTML?: string;
  testingEnabled: boolean;
  presentationCSS: string;
  userCSS: string;
  localization: ReaderLocalization;
  linkPreviews: ReadLinkPreview[];
}

export function validatedReaderConfiguration(value: unknown): ReaderConfiguration | null {
  if (!value || typeof value !== "object") return null;
  const config = value as Partial<ReaderConfiguration>;
  if (config.version !== 6
      || typeof config.documentID !== "string" || !config.documentID
      || config.documentID.length > 4_096
      || typeof config.fingerprint !== "string" || !config.fingerprint
      || config.fingerprint.length > 256
      || !Number.isSafeInteger(config.loadGeneration) || Number(config.loadGeneration) < 0
      || typeof config.selectionEnabled !== "boolean"
      || (config.chatReply !== undefined && typeof config.chatReply !== "boolean")
      || (config.chatReplyPreviousHTML !== undefined && (config.chatReply !== true
        || typeof config.chatReplyPreviousHTML !== 'string' || config.chatReplyPreviousHTML.length > 262_144))
      || typeof config.testingEnabled !== "boolean"
      || typeof config.presentationCSS !== "string"
      || typeof config.userCSS !== "string"
      || !config.localization || typeof config.localization !== "object"
      || !config.localization.strings || typeof config.localization.strings !== "object"
      || !Array.isArray(config.linkPreviews) || config.linkPreviews.length > 128
      ) return null;

  return config as ReaderConfiguration;
}

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

export interface ReadDocumentAttachment {
  id: string;
  filename: string;
  available: boolean;
}

export interface ReaderConfiguration {
  version: 2;
  documentID: string;
  fingerprint: string;
  loadGeneration: number;
  selectionEnabled: boolean;
  testingEnabled: boolean;
  presentationCSS: string;
  userCSS: string;
  localization: ReaderLocalization;
  linkPreviews: ReadLinkPreview[];
  documentAttachments: ReadDocumentAttachment[];
}

export function validatedReaderConfiguration(value: unknown): ReaderConfiguration | null {
  if (!value || typeof value !== "object") return null;
  const config = value as Partial<ReaderConfiguration>;
  if (config.version !== 2
      || typeof config.documentID !== "string" || !config.documentID
      || config.documentID.length > 4_096
      || typeof config.fingerprint !== "string" || !config.fingerprint
      || config.fingerprint.length > 256
      || !Number.isSafeInteger(config.loadGeneration) || Number(config.loadGeneration) < 0
      || typeof config.selectionEnabled !== "boolean"
      || typeof config.testingEnabled !== "boolean"
      || typeof config.presentationCSS !== "string"
      || typeof config.userCSS !== "string"
      || !config.localization || typeof config.localization !== "object"
      || !config.localization.strings || typeof config.localization.strings !== "object"
      || !Array.isArray(config.linkPreviews) || config.linkPreviews.length > 128
      || !Array.isArray(config.documentAttachments)
      || config.documentAttachments.length > 100
      || !config.documentAttachments.every((attachment) => Boolean(attachment)
        && typeof attachment === "object"
        && typeof attachment.id === "string" && attachment.id.length <= 128
        && typeof attachment.filename === "string" && attachment.filename.length <= 1_024
        && typeof attachment.available === "boolean")) return null;
  return config as ReaderConfiguration;
}

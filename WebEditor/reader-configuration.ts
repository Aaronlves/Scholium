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

export interface ReaderConfiguration {
  version: 1;
  documentID: string;
  fingerprint: string;
  loadGeneration: number;
  selectionEnabled: boolean;
  testingEnabled: boolean;
  presentationCSS: string;
  userCSS: string;
  localization: ReaderLocalization;
  linkPreviews: ReadLinkPreview[];
  vectorSymbols: Record<string, string>;
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
      || typeof config.selectionEnabled !== "boolean"
      || typeof config.testingEnabled !== "boolean"
      || typeof config.presentationCSS !== "string"
      || typeof config.userCSS !== "string"
      || !config.localization || typeof config.localization !== "object"
      || !config.localization.strings || typeof config.localization.strings !== "object"
      || !Array.isArray(config.linkPreviews) || config.linkPreviews.length > 128
      || !config.vectorSymbols || typeof config.vectorSymbols !== "object") return null;
  return config as ReaderConfiguration;
}

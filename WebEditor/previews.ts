export interface LinkPreview {
  from: number;
  to: number;
  title: string;
  isEmbedded: boolean;
  fragment?: string;
  htmlBody: string;
}

export function validatedLinkPreviews(value: unknown, documentLength: number): LinkPreview[] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 128).flatMap((candidate): LinkPreview[] => {
    if (!candidate || typeof candidate !== "object") return [];
    const record = candidate as Record<string, unknown>;
    const from = Number.isInteger(record.from) ? Number(record.from) : -1;
    const to = Number.isInteger(record.to) ? Number(record.to) : -1;
    const title = typeof record.title === "string" ? record.title.slice(0, 240).trim() : "";
    const isEmbedded = record.isEmbedded === true;
    const htmlBody = typeof record.htmlBody === "string"
      ? (isEmbedded ? record.htmlBody : record.htmlBody.slice(0, 24_000))
      : "";
    const fragment = typeof record.fragment === "string"
      ? record.fragment.slice(0, 240).trim() || undefined
      : undefined;
    if (from < 0 || to <= from || to > documentLength || !title || !htmlBody) return [];
    return [{from, to, title, isEmbedded, fragment, htmlBody}];
  });
}

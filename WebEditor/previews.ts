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

/** Returns only the definition referenced by `identifier`, never the full footnote section. */
export function footnotePreviewContent(
  source: string,
  identifier: string,
  excluded: readonly SourceRange[] = [],
  dialect: FootnoteDialect = scholiumFootnoteDialect,
): string | null {
  const requested = identifier.trim();
  if (!requested || requested.length > 240) return null;
  const definition = footnotePresentation(source, excluded, dialect).definitions
    .find((candidate) => candidate.identifier === requested);
  const content = definition?.content.trim().slice(0, 1_600) ?? "";
  return content || null;
}

export function footnoteReferenceAt(
  source: string,
  position: number,
  excluded: readonly SourceRange[] = [],
  dialect: FootnoteDialect = scholiumFootnoteDialect,
): string | null {
  if (!supportsFootnoteDialect(dialect)) return null;
  if (!Number.isInteger(position) || position < 0 || position > source.length) return null;
  for (const match of source.matchAll(/\[\^([^\]\n]{1,240})\]/g)) {
    const from = match.index;
    const to = from + match[0].length;
    if (excluded.some((range) => range.from < to && range.to > from)) continue;
    const lineStart = source.lastIndexOf("\n", from - 1) + 1;
    if (/^ {0,3}\[\^[^\]]+\]:/.test(source.slice(lineStart, to + 1))) continue;
    if (position >= from && position <= to) return match[1];
  }
  return null;
}
import {
  footnotePresentation,
  scholiumFootnoteDialect,
  supportsFootnoteDialect,
  type FootnoteDialect,
  type SourceRange,
} from "./footnote-presentation";

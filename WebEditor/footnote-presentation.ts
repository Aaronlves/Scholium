import type {MarkdownEditingDialect} from "./protocol";

export type FootnoteDialect = MarkdownEditingDialect["footnotes"];

export const scholiumFootnoteDialect: FootnoteDialect = {
  namedReferenceOpening: "[^",
  namedReferenceClosing: "]",
  definitionSeparator: ":",
  inlineOpening: "^[",
  continuationIndentSpaces: 2,
  allowsTabContinuation: true,
  caseSensitiveIdentifiers: true,
  ordinalByFirstReference: true,
};

export function supportsFootnoteDialect(dialect: FootnoteDialect) {
  return dialect.namedReferenceOpening === scholiumFootnoteDialect.namedReferenceOpening
    && dialect.namedReferenceClosing === scholiumFootnoteDialect.namedReferenceClosing
    && dialect.definitionSeparator === scholiumFootnoteDialect.definitionSeparator
    && dialect.inlineOpening === scholiumFootnoteDialect.inlineOpening
    && dialect.continuationIndentSpaces === scholiumFootnoteDialect.continuationIndentSpaces
    && dialect.allowsTabContinuation === scholiumFootnoteDialect.allowsTabContinuation
    && dialect.caseSensitiveIdentifiers === scholiumFootnoteDialect.caseSensitiveIdentifiers
    && dialect.ordinalByFirstReference === scholiumFootnoteDialect.ordinalByFirstReference;
}

export interface SourceRange {
  from: number;
  to: number;
}

export interface FootnoteDefinitionPresentation extends SourceRange {
  identifier: string;
  content: string;
  contentFrom: number;
  ordinal: number | null;
  isInline: boolean;
}

export interface FootnoteReferencePresentation extends SourceRange {
  identifier: string;
  ordinal: number;
  occurrence: number;
  isInline: boolean;
  definitionFrom: number | null;
}

export interface FootnotePresentation {
  definitions: FootnoteDefinitionPresentation[];
  references: FootnoteReferencePresentation[];
}

interface LineSpan {
  from: number;
  contentTo: number;
  to: number;
  text: string;
}

interface RawDefinition extends SourceRange {
  identifier: string;
  content: string;
  contentFrom: number;
  isInline: boolean;
  marker: SourceRange;
}

interface RawReference extends SourceRange {
  identifier: string;
  isInline: boolean;
  inlineContent: string | null;
}

function sourceLines(source: string): LineSpan[] {
  if (source.length === 0) return [];
  const lines: LineSpan[] = [];
  let from = 0;
  while (from < source.length) {
    const newline = source.indexOf("\n", from);
    const contentTo = newline < 0 ? source.length : newline;
    const to = newline < 0 ? source.length : newline + 1;
    const raw = source.slice(from, contentTo);
    const text = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    lines.push({from, contentTo: from + text.length, to, text});
    from = to;
  }
  return lines;
}

function overlaps(ranges: readonly SourceRange[], from: number, to: number) {
  return ranges.some((range) => range.from < to && range.to > from);
}

function isEscaped(source: string, offset: number) {
  let backslashes = 0;
  for (let index = offset - 1; index >= 0 && source[index] === "\\"; index -= 1) {
    backslashes += 1;
  }
  return backslashes % 2 === 1;
}

/**
 * Builds the source-located Live Preview projection for Scholium footnotes.
 * It follows the Contracts dialect: identifiers are case-sensitive, ordinals
 * follow first-reference order, continuations require two spaces or a tab,
 * and duplicate definitions retain only their first semantic definition.
 * The result is presentation-only and never reconstructs Markdown.
 */
export function footnotePresentation(
  source: string,
  excluded: readonly SourceRange[] = [],
  dialect: FootnoteDialect = scholiumFootnoteDialect,
): FootnotePresentation {
  if (!supportsFootnoteDialect(dialect)) return {definitions: [], references: []};
  const lines = sourceLines(source);
  const rawDefinitions: RawDefinition[] = [];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (overlaps(excluded, line.from, line.contentTo)) continue;
    const match = /^\[\^([^\]\r\n]+)\]:[ \t]*(.*)$/.exec(line.text);
    if (!match) continue;

    const parts = [match[2]];
    const firstLineContentFrom = line.contentTo - match[2].length;
    let contentFrom = firstLineContentFrom + (match[2].match(/^\s*/)?.[0].length ?? 0);
    let foundContentStart = /\S/.test(match[2]);
    let to = line.to;
    let continuation = index + 1;
    while (continuation < lines.length) {
      const candidate = lines[continuation];
      if (!(candidate.text.startsWith("  ") || candidate.text.startsWith("\t") || candidate.text.length === 0)) break;
      // Remove one continuation indent while preserving deeper indentation,
      // which carries nested Markdown structure inside the definition.
      const continuationText = candidate.text.replace(/^(?: {2}|\t)/, "");
      if (!foundContentStart && /\S/.test(continuationText)) {
        const removedIndent = candidate.text.length - continuationText.length;
        const leadingWhitespace = continuationText.match(/^\s*/)?.[0].length ?? 0;
        contentFrom = candidate.from + removedIndent + leadingWhitespace;
        foundContentStart = true;
      }
      parts.push(continuationText);
      to = candidate.to;
      continuation += 1;
    }
    rawDefinitions.push({
      identifier: match[1],
      content: parts.join("\n").trim(),
      contentFrom,
      from: line.from,
      to,
      isInline: false,
      marker: {from: line.from, to: line.contentTo},
    });
    index = continuation - 1;
  }

  const rawReferences: RawReference[] = [];
  for (const match of source.matchAll(/\[\^([^\]\r\n]+)\]/g)) {
    const from = match.index;
    const to = from + match[0].length;
    if (overlaps(excluded, from, to)
      || rawDefinitions.some((definition) => overlaps([definition.marker], from, to))
      || isEscaped(source, from)) continue;
    rawReferences.push({
      identifier: match[1],
      from,
      to,
      isInline: false,
      inlineContent: null,
    });
  }

  let inlineCounter = 0;
  for (const match of source.matchAll(/\^\[([^\]\r\n]+)\]/g)) {
    const from = match.index;
    const to = from + match[0].length;
    if (overlaps(excluded, from, to) || isEscaped(source, from)) continue;
    inlineCounter += 1;
    const identifier = `inline-${inlineCounter}`;
    rawReferences.push({
      identifier,
      from,
      to,
      isInline: true,
      inlineContent: match[1],
    });
    rawDefinitions.push({
      identifier,
      content: match[1],
      contentFrom: from + scholiumFootnoteDialect.inlineOpening.length,
      from,
      to,
      isInline: true,
      marker: {from, to},
    });
  }
  rawReferences.sort((left, right) => left.from - right.from);

  const ordinalByIdentifier = new Map<string, number>();
  const occurrenceByIdentifier = new Map<string, number>();
  for (const reference of rawReferences) {
    if (!ordinalByIdentifier.has(reference.identifier)) {
      ordinalByIdentifier.set(reference.identifier, ordinalByIdentifier.size + 1);
    }
    occurrenceByIdentifier.set(
      reference.identifier,
      (occurrenceByIdentifier.get(reference.identifier) ?? 0) + 1,
    );
  }

  const firstDefinitionByIdentifier = new Map<string, RawDefinition>();
  for (const definition of rawDefinitions) {
    if (!firstDefinitionByIdentifier.has(definition.identifier)) {
      firstDefinitionByIdentifier.set(definition.identifier, definition);
    }
  }

  occurrenceByIdentifier.clear();
  const references = rawReferences.map((reference): FootnoteReferencePresentation => {
    const occurrence = (occurrenceByIdentifier.get(reference.identifier) ?? 0) + 1;
    occurrenceByIdentifier.set(reference.identifier, occurrence);
    return {
      identifier: reference.identifier,
      ordinal: ordinalByIdentifier.get(reference.identifier)!,
      occurrence,
      isInline: reference.isInline,
      definitionFrom: firstDefinitionByIdentifier.get(reference.identifier)?.from ?? null,
      from: reference.from,
      to: reference.to,
    };
  });

  const definitions = [...firstDefinitionByIdentifier.values()]
    .map((definition): FootnoteDefinitionPresentation => ({
      identifier: definition.identifier,
      content: definition.content,
      contentFrom: definition.contentFrom,
      ordinal: ordinalByIdentifier.get(definition.identifier) ?? null,
      isInline: definition.isInline,
      from: definition.from,
      to: definition.to,
    }))
    .sort((left, right) => {
      const leftOrdinal = left.ordinal ?? Number.MAX_SAFE_INTEGER;
      const rightOrdinal = right.ordinal ?? Number.MAX_SAFE_INTEGER;
      return leftOrdinal === rightOrdinal ? left.from - right.from : leftOrdinal - rightOrdinal;
    });

  return {definitions, references};
}

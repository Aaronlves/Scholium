import type {MarkdownEditingDialect} from "./protocol";

export function linkTargetAt(source: string, offset: number): string | null {
  if (offset < 0 || offset > source.length) return null;
  const lineFrom = source.lastIndexOf("\n", Math.max(0, offset - 1)) + 1;
  const newline = source.indexOf("\n", offset);
  const lineTo = newline < 0 ? source.length : newline;
  const line = source.slice(lineFrom, lineTo);
  for (const match of line.matchAll(/(?:[+\-?])?\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g)) {
    const from = lineFrom + match.index;
    const to = from + match[0].length;
    if (offset >= from && offset <= to) return match[1].trim();
  }
  for (const match of line.matchAll(/\[[^\]\n]+\]\(([^)\n]+)\)/g)) {
    const from = lineFrom + match.index;
    const to = from + match[0].length;
    if (offset >= from && offset <= to) return match[1].trim();
  }
  return null;
}

export interface DialectSemanticProjection {
  callouts: string[];
  links: Array<{target: string; vectorKind: string | null}>;
  footnoteDefinitions: string[];
  footnoteReferences: string[];
}

export function projectDialectSemantics(source: string, dialect: MarkdownEditingDialect): DialectSemanticProjection {
  const canonicalCallout = (raw: string) => {
    const value = raw.toLowerCase().replace(/:+$/, "").trim();
    return dialect.callouts.find((callout) => callout.identifier === value || callout.aliases.includes(value))?.identifier ?? "neutral";
  };
  const callouts = Array.from(source.matchAll(/^\s*(?:>\s*)+\[!([^\]]+)\]/gm), (match) => canonicalCallout(match[1]));
  const links: DialectSemanticProjection["links"] = [];
  for (const match of source.matchAll(/([+\-?]?)\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g)) {
    const operator = dialect.vectorLinkOperators.find((candidate) => candidate.marker === match[1]);
    links.push({target: match[2].trim(), vectorKind: operator?.kind ?? "neutral"});
  }
  for (const match of source.matchAll(/\[[^\]\n]+\]\(([^)\n]+)\)/g)) {
    links.push({target: match[1].trim(), vectorKind: null});
  }
  const footnoteDefinitions = Array.from(source.matchAll(/^\s*\[\^([^\]]+)\]:/gm), (match) => match[1]);
  const definitionSpans = Array.from(source.matchAll(/^\s*\[\^[^\]]+\]:.*$/gm), (match) => ({from: match.index, to: match.index + match[0].length}));
  const footnoteReferences = Array.from(source.matchAll(/\[\^([^\]]+)\]/g)).flatMap((match) => {
    const inDefinition = definitionSpans.some((span) => match.index >= span.from && match.index < span.to);
    return inDefinition ? [] : [match[1]];
  });
  return {callouts, links, footnoteDefinitions, footnoteReferences};
}

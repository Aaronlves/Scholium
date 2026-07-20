import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree, syntaxTree} from "@codemirror/language";
import type {MarkdownEditingDialect} from "./protocol";
import {markdownLiteralRanges, scanMath} from "./math";
import {footnotePresentation} from "./footnote-presentation";
import {scholiumNoteLanguage} from "./language";

function intersects(
  range: {from: number; to: number},
  candidates: Array<{from: number; to: number}>,
): boolean {
  return candidates.some((candidate) => candidate.from < range.to && range.from < candidate.to);
}

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
  footnoteDefinitionContents: string[];
  footnoteReferences: string[];
  mathExpressions: Array<{kind: "inline" | "display"; content: string}>;
  sourceSlices: {
    calloutHeaders: string[];
    links: string[];
    footnoteDefinitions: string[];
    footnoteReferences: string[];
    mathExpressions: Array<{source: string; content: string}>;
  };
}

export type BaseBlockKind =
  | "paragraph"
  | "heading"
  | "blockQuote"
  | "code"
  | "unorderedList"
  | "orderedList"
  | "listItem"
  | "table"
  | "thematicBreak"
  | "html";

export type BaseInlineKind = "strong" | "emphasis" | "strikethrough" | "code" | "link" | "image";

export interface BaseSyntaxProjection {
  blocks: Array<{kind: BaseBlockKind; from: number; to: number; source: string}>;
  inlines: Array<{kind: BaseInlineKind; from: number; to: number; source: string}>;
}

function normalizedParserInput(source: string) {
  let exactOffset = source.charCodeAt(0) === 0xfeff ? 1 : 0;
  let normalized = "";
  const exactOffsets = [exactOffset];
  while (exactOffset < source.length) {
    const character = source.charCodeAt(exactOffset);
    if (character === 0x0d) {
      exactOffset += source.charCodeAt(exactOffset + 1) === 0x0a ? 2 : 1;
      normalized += "\n";
    } else {
      normalized += source[exactOffset];
      exactOffset += 1;
    }
    exactOffsets.push(exactOffset);
  }
  return {normalized, exactOffsets};
}

function compareLocatedSyntax(
  left: {kind: string; from: number; to: number},
  right: {kind: string; from: number; to: number},
) {
  return left.from - right.from || right.to - left.to || left.kind.localeCompare(right.kind);
}

function withoutTerminalLineEnding(source: string, from: number, to: number) {
  if (to > from && source.charCodeAt(to - 1) === 0x0a) {
    to -= 1;
    if (to > from && source.charCodeAt(to - 1) === 0x0d) to -= 1;
  } else if (to > from && source.charCodeAt(to - 1) === 0x0d) {
    to -= 1;
  }
  return to;
}

/**
 * Projects the mode-neutral CommonMark/GFM node catalog used by both render
 * adapters. Source offsets are mapped back to the exact UTF-16 note buffer.
 * Terminal line endings are not owned by a semantic block in this contract.
 */
export function projectBaseSyntax(source: string): BaseSyntaxProjection {
  const parserInput = normalizedParserInput(source);
  const state = EditorState.create({doc: parserInput.normalized, extensions: [scholiumNoteLanguage]});
  const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
  if (!tree) throw new Error("Could not complete the base Markdown syntax tree.");
  const blocks: BaseSyntaxProjection["blocks"] = [];
  const inlines: BaseSyntaxProjection["inlines"] = [];
  const blockKinds = new Map<string, BaseBlockKind>([
    ["Paragraph", "paragraph"],
    ["Blockquote", "blockQuote"],
    ["FencedCode", "code"],
    ["CodeBlock", "code"],
    ["BulletList", "unorderedList"],
    ["OrderedList", "orderedList"],
    ["ListItem", "listItem"],
    ["Table", "table"],
    ["HorizontalRule", "thematicBreak"],
    ["HTMLBlock", "html"],
  ]);
  const inlineKinds = new Map<string, BaseInlineKind>([
    ["StrongEmphasis", "strong"],
    ["Emphasis", "emphasis"],
    ["Strikethrough", "strikethrough"],
    ["InlineCode", "code"],
    ["Link", "link"],
    ["Autolink", "link"],
    ["Image", "image"],
  ]);
  tree.iterate({
    enter(node) {
      const exactFrom = parserInput.exactOffsets[node.from];
      const exactTo = parserInput.exactOffsets[node.to];
      const heading = /^(?:ATX|Setext)Heading[1-6]$/.test(node.name);
      const blockKind = heading ? "heading" : blockKinds.get(node.name);
      if (blockKind) {
        const to = withoutTerminalLineEnding(source, exactFrom, exactTo);
        blocks.push({kind: blockKind, from: exactFrom, to, source: source.slice(exactFrom, to)});
      }
      if (node.name === "Task") {
        const raw = source.slice(exactFrom, exactTo);
        const marker = /^\[[ xX]\][ \t]*/.exec(raw);
        if (marker && marker[0].length < raw.length) {
          const from = exactFrom + marker[0].length;
          blocks.push({kind: "paragraph", from, to: exactTo, source: source.slice(from, exactTo)});
        }
      }
      const inlineKind = inlineKinds.get(node.name);
      if (inlineKind) {
        inlines.push({
          kind: inlineKind,
          from: exactFrom,
          to: exactTo,
          source: source.slice(exactFrom, exactTo),
        });
      }
    },
  });
  blocks.sort(compareLocatedSyntax);
  inlines.sort(compareLocatedSyntax);
  return {blocks, inlines};
}

export function projectDialectSemantics(source: string, dialect: MarkdownEditingDialect): DialectSemanticProjection {
  const canonicalCallout = (raw: string) => {
    const value = raw.toLowerCase().replace(/:+$/, "").trim();
    return dialect.callouts.find(
      (callout) => callout.identifier === value || callout.aliases.includes(value),
    )?.identifier ?? value;
  };
  const parserInput = normalizedParserInput(source);
  const state = EditorState.create({doc: parserInput.normalized, extensions: [scholiumNoteLanguage]});
  const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
  if (!tree) throw new Error("Could not complete the Scholium dialect syntax tree.");
  const rangesByName = new Map<string, Array<{from: number; to: number}>>();
  tree.iterate({
    enter(node) {
      if (![
        "Callout", "WikiLink", "VectorLink", "Link", "Autolink",
        "FootnoteDefinition", "FootnoteReference", "InlineFootnote",
        "InlineMath", "BlockMath",
      ].includes(node.name)) return;
      const ranges = rangesByName.get(node.name) ?? [];
      ranges.push({
        from: parserInput.exactOffsets[node.from],
        to: parserInput.exactOffsets[node.to],
      });
      rangesByName.set(node.name, ranges);
    },
  });
  const ranges = (...names: string[]) => names.flatMap((name) => rangesByName.get(name) ?? []);
  const keyedRanges = (...names: string[]) => new Set(
    ranges(...names).map(({from, to}) => `${from}:${to}`),
  );
  const excluded = markdownLiteralRanges(source);
  const locatedCallouts = ranges("Callout").flatMap(({from, to}) => {
    if (intersects({from, to}, excluded)) return [];
    const lineEnd = source.indexOf("\n", from);
    const headerTo = lineEnd < 0 || lineEnd > to ? to : lineEnd - (source[lineEnd - 1] === "\r" ? 1 : 0);
    const header = source.slice(from, headerTo);
    const match = /^(?:>[ \t]*)+\[!([^\]]+)\]/.exec(header);
    return match ? [{from, to: headerTo, kind: canonicalCallout(match[1])}] : [];
  });
  const callouts = locatedCallouts.map(({kind}) => kind);
  const locatedLinks: Array<{from: number; to: number; target: string; vectorKind: string | null}> = [];
  for (const {from, to} of ranges("WikiLink", "VectorLink")) {
    if (intersects({from, to}, excluded)) continue;
    const raw = source.slice(from, to);
    const match = /^(!?)([+\-?]?)\[\[([^\]|]+)(?:\|[^\]]+)?\]\]$/.exec(raw);
    if (!match) continue;
    const operator = dialect.vectorLinkOperators.find((candidate) => candidate.marker === match[2]);
    const isEmbed = match[1] === "!";
    locatedLinks.push({
      from,
      to,
      target: match[3].split("#", 1)[0].trim(),
      vectorKind: isEmbed ? null : operator?.kind ?? "neutral",
    });
  }
  for (const {from, to} of ranges("Link")) {
    if (intersects({from, to}, excluded)) continue;
    const match = /^\[[^\]\n]+\]\(([^)\n]+)\)$/.exec(source.slice(from, to));
    if (!match) continue;
    const rawTarget = match[1].trim().replace(/^<|>$/g, "");
    const path = rawTarget.split("#", 1)[0];
    let target = path;
    try { target = decodeURIComponent(path); } catch { target = path; }
    locatedLinks.push({
      from,
      to,
      target,
      vectorKind: null,
    });
  }
  locatedLinks.sort((left, right) => left.from - right.from);
  const links = locatedLinks.map(({target, vectorKind}) => ({target, vectorKind}));
  const footnoteRanges = footnotePresentation(source, excluded, dialect.footnotes);
  const definitionKeys = keyedRanges("FootnoteDefinition", "InlineFootnote");
  const referenceKeys = keyedRanges("FootnoteReference", "InlineFootnote");
  const footnotes = {
    definitions: footnoteRanges.definitions.filter(({from, to}) => definitionKeys.has(`${from}:${to}`)),
    references: footnoteRanges.references.filter(({from, to}) => referenceKeys.has(`${from}:${to}`)),
  };
  const footnoteDefinitions = footnotes.definitions.map((definition) => definition.identifier);
  const footnoteDefinitionContents = footnotes.definitions.map((definition) => definition.content);
  const footnoteReferences = footnotes.references.map((reference) => reference.identifier);
  const mathKeys = keyedRanges("InlineMath", "BlockMath");
  const locatedMath = scanMath(source, dialect.mathematics)
    .filter(({from, to}) => mathKeys.has(`${from}:${to}`));
  const mathExpressions = locatedMath.map(({kind, content}) => ({kind, content}));
  const sourceSlices = {
    calloutHeaders: locatedCallouts.map(({from, to}) => source.slice(from, to)),
    links: locatedLinks.map(({from, to}) => source.slice(from, to)),
    footnoteDefinitions: footnotes.definitions.map(({from, to}) => source.slice(from, to)),
    footnoteReferences: footnotes.references.map(({from, to}) => source.slice(from, to)),
    mathExpressions: locatedMath.map(({from, to, contentFrom, contentTo}) => ({
      source: source.slice(from, to),
      content: source.slice(contentFrom, contentTo),
    })),
  };
  return {
    callouts,
    links,
    footnoteDefinitions,
    footnoteDefinitionContents,
    footnoteReferences,
    mathExpressions,
    sourceSlices,
  };
}

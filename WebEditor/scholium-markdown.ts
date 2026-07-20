import type {
  BlockContext,
  InlineContext,
  Line,
  MarkdownConfig,
} from "@lezer/markdown";

const SPACE = 0x20;
const TAB = 0x09;
const LINE_FEED = 0x0a;
const CARRIAGE_RETURN = 0x0d;

function isHorizontalWhitespace(character: number) {
  return character === SPACE || character === TAB;
}

function isEscaped(cx: InlineContext, position: number) {
  let backslashes = 0;
  for (let cursor = position - 1; cursor >= cx.offset && cx.char(cursor) === 0x5c; cursor -= 1) {
    backslashes += 1;
  }
  return backslashes % 2 === 1;
}

function wikiLinkEnd(cx: InlineContext, contentFrom: number) {
  let separator = -1;
  for (let cursor = contentFrom; cursor < cx.end - 1; cursor += 1) {
    const character = cx.char(cursor);
    if (character === LINE_FEED || character === CARRIAGE_RETURN || character === 0x5b) return null;
    if (character === 0x7c && separator < 0) separator = cursor;
    if (character === 0x5d && cx.char(cursor + 1) === 0x5d) {
      const targetTo = separator < 0 ? cursor : separator;
      if (cx.slice(contentFrom, targetTo).trim().length === 0) return null;
      return {separator, closingFrom: cursor, to: cursor + 2};
    }
  }
  return null;
}

function addWikiLink(
  cx: InlineContext,
  from: number,
  openingFrom: number,
  nodeName: "WikiLink" | "VectorLink",
  prefixName: "WikiLinkOpenMark" | "WikiEmbedMark" | "VectorLinkMark",
) {
  const contentFrom = openingFrom + 2;
  const end = wikiLinkEnd(cx, contentFrom);
  if (!end) return -1;
  const targetTo = end.separator < 0 ? end.closingFrom : end.separator;
  const children = [
    cx.elt(prefixName, from, contentFrom),
    cx.elt("WikiLinkTarget", contentFrom, targetTo),
  ];
  if (end.separator >= 0) {
    children.push(cx.elt("WikiLinkAliasMark", end.separator, end.separator + 1));
    if (end.separator + 1 < end.closingFrom) {
      children.push(cx.elt("WikiLinkAlias", end.separator + 1, end.closingFrom));
    }
  }
  children.push(cx.elt("WikiLinkCloseMark", end.closingFrom, end.to));
  return cx.addElement(cx.elt(nodeName, from, end.to, children));
}

function parseObsidianInlineComment(cx: InlineContext, next: number, position: number) {
  if (next !== 0x25 || cx.char(position + 1) !== 0x25) return -1;
  for (let cursor = position + 2; cursor < cx.end - 1; cursor += 1) {
    if (cx.char(cursor) === 0x25 && cx.char(cursor + 1) === 0x25) {
      return cx.addElement(cx.elt("ObsidianComment", position, cursor + 2));
    }
  }
  return cx.addElement(cx.elt("UnclosedObsidianComment", position, cx.end));
}

function parseVectorLink(cx: InlineContext, next: number, position: number) {
  if (![0x2b, 0x2d, 0x3f].includes(next)
    || cx.char(position + 1) !== 0x5b
    || cx.char(position + 2) !== 0x5b) return -1;
  if (isEscaped(cx, position)) return -1;
  if (position > cx.offset) {
    const priorText = cx.slice(Math.max(cx.offset, position - 2), position);
    const previous = Array.from(priorText).at(-1) ?? "";
    if (/\p{L}|\p{N}/u.test(previous) || ["_", "\\", "!", "+", "-", "?"].includes(previous)) {
      return -1;
    }
  }
  return addWikiLink(cx, position, position + 1, "VectorLink", "VectorLinkMark");
}

function parseWikiLink(cx: InlineContext, next: number, position: number) {
  if (next !== 0x5b || cx.char(position + 1) !== 0x5b) return -1;
  return addWikiLink(cx, position, position, "WikiLink", "WikiLinkOpenMark");
}

function parseWikiEmbed(cx: InlineContext, next: number, position: number) {
  if (next !== 0x21 || cx.char(position + 1) !== 0x5b || cx.char(position + 2) !== 0x5b) return -1;
  return addWikiLink(cx, position, position + 1, "WikiLink", "WikiEmbedMark");
}

function parseFootnoteReference(cx: InlineContext, next: number, position: number) {
  if (next !== 0x5b || cx.char(position + 1) !== 0x5e) return -1;
  for (let cursor = position + 2; cursor < cx.end; cursor += 1) {
    const character = cx.char(cursor);
    if (character === LINE_FEED || character === CARRIAGE_RETURN) return -1;
    if (character !== 0x5d) continue;
    if (cursor === position + 2) return -1;
    return cx.addElement(cx.elt("FootnoteReference", position, cursor + 1, [
      cx.elt("FootnoteOpenMark", position, position + 2),
      cx.elt("FootnoteIdentifier", position + 2, cursor),
      cx.elt("FootnoteCloseMark", cursor, cursor + 1),
    ]));
  }
  return -1;
}

function parseInlineFootnote(cx: InlineContext, next: number, position: number) {
  if (next !== 0x5e || cx.char(position + 1) !== 0x5b) return -1;
  for (let cursor = position + 2; cursor < cx.end; cursor += 1) {
    const character = cx.char(cursor);
    if (character === LINE_FEED || character === CARRIAGE_RETURN) return -1;
    if (character !== 0x5d || isEscaped(cx, cursor)) continue;
    if (cx.slice(position + 2, cursor).trim().length === 0) return -1;
    return cx.addElement(cx.elt("InlineFootnote", position, cursor + 1, [
      cx.elt("InlineFootnoteOpenMark", position, position + 2),
      cx.elt("FootnoteContent", position + 2, cursor),
      cx.elt("FootnoteCloseMark", cursor, cursor + 1),
    ]));
  }
  return -1;
}

function parseInlineMath(cx: InlineContext, next: number, position: number) {
  if (next !== 0x24) return -1;
  let openingTo = position + 1;
  while (cx.char(openingTo) === 0x24) openingTo += 1;
  const delimiterLength = openingTo - position;
  for (let cursor = openingTo; cursor < cx.end; cursor += 1) {
    const character = cx.char(cursor);
    if (character === LINE_FEED || character === CARRIAGE_RETURN) return -1;
    if (character !== 0x24 || isEscaped(cx, cursor)) continue;
    let closingTo = cursor + 1;
    while (cx.char(closingTo) === 0x24) closingTo += 1;
    if (closingTo - cursor !== delimiterLength) {
      cursor = closingTo - 1;
      continue;
    }
    if (cx.slice(openingTo, cursor).trim().length === 0) return -1;
    return cx.addElement(cx.elt("InlineMath", position, closingTo, [
      cx.elt("MathMark", position, openingTo),
      cx.elt("MathContent", openingTo, cursor),
      cx.elt("MathMark", cursor, closingTo),
    ]));
  }
  return -1;
}

function parseHighlight(cx: InlineContext, next: number, position: number) {
  if (next !== 0x3d || cx.char(position + 1) !== 0x3d || cx.char(position + 2) === 0x3d) return -1;
  for (let cursor = position + 2; cursor < cx.end - 1; cursor += 1) {
    const character = cx.char(cursor);
    if (character === LINE_FEED || character === CARRIAGE_RETURN) return -1;
    if (character !== 0x3d || cx.char(cursor + 1) !== 0x3d
      || cx.char(cursor + 2) === 0x3d || isEscaped(cx, cursor)) continue;
    if (cx.slice(position + 2, cursor).trim().length === 0) return -1;
    return cx.addElement(cx.elt("Highlight", position, cursor + 2, [
      cx.elt("HighlightMark", position, position + 2),
      cx.elt("HighlightContent", position + 2, cursor),
      cx.elt("HighlightMark", cursor, cursor + 2),
    ]));
  }
  return -1;
}

function displayMathFence(line: Line) {
  if (line.next !== 0x24 || line.text.charCodeAt(line.pos + 1) !== 0x24) return null;
  let cursor = line.pos + 2;
  while (line.text.charCodeAt(cursor) === 0x24) cursor += 1;
  const length = cursor - line.pos;
  while (cursor < line.text.length && isHorizontalWhitespace(line.text.charCodeAt(cursor))) cursor += 1;
  return cursor === line.text.length ? {position: line.pos, length} : null;
}

function parseBlockMath(cx: BlockContext, line: Line) {
  const opening = displayMathFence(line);
  if (!opening) return false;
  const from = cx.lineStart + opening.position;
  const openingTo = from + opening.length;
  const contentFrom = cx.lineStart + line.text.length + 1;
  while (cx.nextLine()) {
    const closing = displayMathFence(line);
    if (!closing || closing.length < opening.length) continue;
    const closingFrom = cx.lineStart + closing.position;
    const to = closingFrom + closing.length;
    const children = [cx.elt("MathMark", from, openingTo)];
    if (contentFrom < closingFrom) children.push(cx.elt("MathContent", contentFrom, closingFrom));
    children.push(cx.elt("MathMark", closingFrom, to));
    cx.nextLine();
    cx.addElement(cx.elt("BlockMath", from, to, children));
    return true;
  }
  const to = Math.max(openingTo, cx.prevLineEnd());
  cx.addElement(cx.elt("UnclosedBlockMath", from, to, [
    cx.elt("MathMark", from, openingTo),
    ...(contentFrom < to ? [cx.elt("MathContent", contentFrom, to)] : []),
  ]));
  return true;
}

function obsidianCommentClosing(text: string, from: number) {
  const closing = text.indexOf("%%", from);
  if (closing < 0 || text.slice(closing + 2).trim().length > 0) return -1;
  return closing;
}

function parseObsidianCommentBlock(cx: BlockContext, line: Line) {
  const openingText = line.text.slice(line.pos);
  if (!openingText.startsWith("%%")) return false;
  const from = cx.lineStart + line.pos;
  const firstClosing = obsidianCommentClosing(openingText, 2);
  if (firstClosing >= 0) {
    const to = from + firstClosing + 2;
    cx.nextLine();
    cx.addElement(cx.elt("ObsidianCommentBlock", from, to));
    return true;
  }
  while (cx.nextLine()) {
    const closing = obsidianCommentClosing(line.text, 0);
    if (closing < 0) continue;
    const to = cx.lineStart + closing + 2;
    cx.nextLine();
    cx.addElement(cx.elt("ObsidianCommentBlock", from, to));
    return true;
  }
  cx.addElement(cx.elt("UnclosedObsidianCommentBlock", from, Math.max(from + 2, cx.prevLineEnd())));
  return true;
}

function quoteMarkerSize(line: Line) {
  if (line.next !== 0x3e) return -1;
  return isHorizontalWhitespace(line.text.charCodeAt(line.pos + 1)) ? 2 : 1;
}

function isCalloutOpening(line: Line) {
  const size = quoteMarkerSize(line);
  if (size < 0) return false;
  const content = line.text.slice(line.pos + size);
  return /^\[![^\]\r\n]+\]/.test(content);
}

function continueCallout(cx: BlockContext, line: Line) {
  const size = quoteMarkerSize(line);
  if (size < 0) return false;
  line.addMarker(cx.elt("CalloutQuoteMark", cx.lineStart + line.pos, cx.lineStart + line.pos + 1));
  line.moveBase(line.pos + size);
  return true;
}

function parseCallout(cx: BlockContext, line: Line) {
  if (!isCalloutOpening(line)) return false;
  const from = cx.lineStart + line.pos;
  const size = quoteMarkerSize(line);
  cx.startComposite("Callout", line.pos);
  cx.addElement(cx.elt("CalloutQuoteMark", from, from + 1));
  line.moveBase(line.pos + size);
  return null;
}

function parseFootnoteDefinition(cx: BlockContext, line: Line) {
  const source = line.text.slice(line.pos);
  const match = /^\[\^([^\]\r\n]+)\]:[ \t]*/.exec(source);
  if (!match) return false;
  const from = cx.lineStart + line.pos;
  const identifierFrom = from + 2;
  const identifierTo = identifierFrom + match[1].length;
  const contentFrom = from + match[0].length;
  let to = cx.lineStart + line.text.length;
  while (cx.nextLine()) {
    const continuation = line.text.slice(line.basePos);
    if (!(continuation.length === 0 || continuation.startsWith("  ") || continuation.startsWith("\t"))) break;
    to = cx.lineStart + line.text.length;
  }
  if (cx.lineStart > to) to = cx.lineStart;
  const children = [
    cx.elt("FootnoteOpenMark", from, identifierFrom),
    cx.elt("FootnoteIdentifier", identifierFrom, identifierTo),
    cx.elt("FootnoteDefinitionMark", identifierTo, contentFrom),
  ];
  if (contentFrom < to) children.push(cx.elt("FootnoteContent", contentFrom, to));
  cx.addElement(cx.elt("FootnoteDefinition", from, to, children));
  return true;
}

/**
 * The single incremental syntax owner for Scholium's Markdown additions.
 * Nodes locate syntax only. Swift semantics and GraphSnapshot remain the
 * authority for identities, diagnostics, and philosophical relationships.
 */
export const scholiumMarkdownDialect: MarkdownConfig = {
  defineNodes: [
    "WikiLink", "VectorLink", "WikiLinkOpenMark", "WikiEmbedMark", "VectorLinkMark",
    "WikiLinkTarget", "WikiLinkAliasMark", "WikiLinkAlias", "WikiLinkCloseMark",
    "FootnoteReference", {name: "FootnoteDefinition", block: true}, "InlineFootnote",
    "FootnoteOpenMark", "FootnoteIdentifier", "FootnoteDefinitionMark",
    "InlineFootnoteOpenMark", "FootnoteContent", "FootnoteCloseMark",
    "InlineMath", {name: "BlockMath", block: true}, {name: "UnclosedBlockMath", block: true},
    "MathMark", "MathContent",
    "Highlight", "HighlightMark", "HighlightContent",
    {name: "Callout", block: true, composite: continueCallout}, "CalloutQuoteMark",
    "ObsidianComment", "UnclosedObsidianComment",
    {name: "ObsidianCommentBlock", block: true}, {name: "UnclosedObsidianCommentBlock", block: true},
  ],
  parseInline: [
    {name: "ScholiumObsidianComment", parse: parseObsidianInlineComment, before: "Link"},
    {name: "ScholiumVectorLink", parse: parseVectorLink, before: "Link"},
    {name: "ScholiumFootnoteReference", parse: parseFootnoteReference, before: "Link"},
    {name: "ScholiumWikiLink", parse: parseWikiLink, before: "Link"},
    {name: "ScholiumInlineFootnote", parse: parseInlineFootnote, before: "Link"},
    {name: "ScholiumInlineMath", parse: parseInlineMath, before: "Link"},
    {name: "ScholiumHighlight", parse: parseHighlight, before: "Link"},
    {name: "ScholiumWikiEmbed", parse: parseWikiEmbed, before: "Image"},
  ],
  parseBlock: [
    {name: "ScholiumObsidianCommentBlock", parse: parseObsidianCommentBlock, before: "FencedCode"},
    {name: "ScholiumBlockMath", parse: parseBlockMath, before: "FencedCode"},
    {name: "ScholiumCallout", parse: parseCallout, before: "Blockquote"},
    {name: "ScholiumFootnoteDefinition", parse: parseFootnoteDefinition, before: "LinkReference"},
  ],
};

export interface MathDialect {
  inlineDelimiter: string;
  displayDelimiter: string;
  singleDollarInline: boolean;
}

export interface MathProjection {
  kind: "inline" | "display";
  content: string;
  delimiterLength: number;
  from: number;
  to: number;
  contentFrom: number;
  contentTo: number;
}

interface Range {from: number; to: number}
interface LineRange extends Range {contentTo: number}

export function scanMath(source: string, dialect: MathDialect): MathProjection[] {
  if (dialect.inlineDelimiter !== "$" || dialect.displayDelimiter !== "$$") return [];
  const lines = lineRanges(source);
  const excluded = markdownLiteralRanges(source, lines);
  const displays: MathProjection[] = [];
  const displayRanges: Range[] = [];

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const opener = displayFence(source, line);
    if (!opener || intersects(opener, excluded)) continue;
    let closingIndex = -1;
    let closing: Range | null = null;
    for (let candidateIndex = index + 1; candidateIndex < lines.length; candidateIndex += 1) {
      const candidate = displayFence(source, lines[candidateIndex]);
      if (candidate && candidate.to - candidate.from >= opener.to - opener.from && !intersects(candidate, excluded)) {
        closingIndex = candidateIndex;
        closing = candidate;
        break;
      }
    }
    if (!closing || closingIndex < 0) continue;
    const contentFrom = line.to;
    const contentTo = lines[closingIndex].from;
    const range = {from: opener.from, to: closing.to};
    displays.push({
      kind: "display",
      content: source.slice(contentFrom, contentTo).replace(/^[\r\n]+|[\r\n]+$/g, ""),
      delimiterLength: opener.to - opener.from,
      from: range.from,
      to: range.to,
      contentFrom,
      contentTo,
    });
    displayRanges.push(range);
    index = closingIndex;
  }

  const inlineExcluded = excluded.concat(displayRanges);
  const inlines: MathProjection[] = [];
  for (let cursor = 0; cursor < source.length;) {
    if (source.charCodeAt(cursor) !== 0x24) {
      cursor += 1;
      continue;
    }
    const openingStart = cursor;
    while (cursor < source.length && source.charCodeAt(cursor) === 0x24) cursor += 1;
    const delimiterLength = cursor - openingStart;
    const opening = {from: openingStart, to: cursor};
    if (isEscaped(source, openingStart) || intersects(opening, inlineExcluded)) continue;

    let closingStart = -1;
    for (let search = cursor; search < source.length;) {
      if (source.charCodeAt(search) !== 0x24) {
        search += 1;
        continue;
      }
      const runStart = search;
      while (search < source.length && source.charCodeAt(search) === 0x24) search += 1;
      if (search - runStart === delimiterLength && !isEscaped(source, runStart)) {
        closingStart = runStart;
        break;
      }
    }
    if (closingStart <= cursor) continue;
    const whole = {from: openingStart, to: closingStart + delimiterLength};
    if (intersects(whole, inlineExcluded)) continue;
    const raw = source.slice(cursor, closingStart);
    const content = raw.length > 2 && /^\s/.test(raw) && /\s$/.test(raw) && /\S/.test(raw)
      ? raw.slice(1, -1)
      : raw;
    inlines.push({
      kind: "inline",
      content,
      delimiterLength,
      from: whole.from,
      to: whole.to,
      contentFrom: cursor,
      contentTo: closingStart,
    });
    cursor = whole.to;
  }

  return displays.concat(inlines).sort((left, right) => left.from - right.from);
}

function displayFence(source: string, line: LineRange): Range | null {
  let position = line.from;
  let indentation = 0;
  while (position < line.contentTo && source.charCodeAt(position) === 0x20 && indentation < 4) {
    position += 1;
    indentation += 1;
  }
  if (indentation > 3 || position >= line.contentTo || source.charCodeAt(position) !== 0x24 || isEscaped(source, position)) {
    return null;
  }
  const start = position;
  while (position < line.contentTo && source.charCodeAt(position) === 0x24) position += 1;
  const delimiterEnd = position;
  if (delimiterEnd - start < 2) return null;
  while (position < line.contentTo && (source.charCodeAt(position) === 0x20 || source.charCodeAt(position) === 0x09)) {
    position += 1;
  }
  return position === line.contentTo ? {from: start, to: delimiterEnd} : null;
}

function lineRanges(source: string): LineRange[] {
  const lines: LineRange[] = [];
  for (let from = 0; from <= source.length;) {
    let contentTo = from;
    while (contentTo < source.length && source.charCodeAt(contentTo) !== 0x0a && source.charCodeAt(contentTo) !== 0x0d) {
      contentTo += 1;
    }
    let to = contentTo;
    if (to < source.length && source.charCodeAt(to) === 0x0d) to += 1;
    if (to < source.length && source.charCodeAt(to) === 0x0a) to += 1;
    lines.push({from, contentTo, to});
    if (to >= source.length) break;
    from = to;
  }
  return lines;
}

export function markdownLiteralRanges(
  source: string,
  knownLines: LineRange[] = lineRanges(source),
): Range[] {
  const lines = knownLines;
  const ranges: Range[] = [];
  const firstLine = lines[0];
  if (firstLine && source.slice(firstLine.from, firstLine.contentTo).replace(/^\uFEFF/, "") === "---") {
    for (let index = 1; index < lines.length; index += 1) {
      const value = source.slice(lines[index].from, lines[index].contentTo);
      if (value === "---" || value === "...") {
        ranges.push({from: firstLine.from, to: lines[index].to});
        break;
      }
    }
  }

  for (let index = 0; index < lines.length; index += 1) {
    const value = source.slice(lines[index].from, lines[index].contentTo);
    const opening = value.match(/^ {0,3}(`{3,}|~{3,})/);
    if (!opening) continue;
    const marker = opening[1][0];
    const length = opening[1].length;
    let closingIndex = index;
    for (let candidate = index + 1; candidate < lines.length; candidate += 1) {
      const candidateValue = source.slice(lines[candidate].from, lines[candidate].contentTo);
      const closing = candidateValue.match(new RegExp(`^ {0,3}${marker === "`" ? "`" : "~"}{${length},}[ \\t]*$`));
      if (closing) {
        closingIndex = candidate;
        break;
      }
    }
    ranges.push({from: lines[index].from, to: lines[closingIndex].to});
    index = closingIndex;
  }

  const blockTags = "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul";
  const blockStart = new RegExp(`^ {0,3}<(${blockTags})(?:[\\t >]|/?>)`, "i");
  for (let index = 0; index < lines.length; index += 1) {
    const value = source.slice(lines[index].from, lines[index].contentTo);
    if (!blockStart.test(value)) continue;
    let closingIndex = lines.length - 1;
    for (let candidate = index + 1; candidate < lines.length; candidate += 1) {
      if (source.slice(lines[candidate].from, lines[candidate].contentTo).trim().length === 0) {
        closingIndex = candidate - 1;
        break;
      }
    }
    ranges.push({from: lines[index].from, to: lines[closingIndex].to});
    index = closingIndex;
  }

  for (const delimiters of [["%%", "%%"], ["<!--", "-->"]] as const) {
    for (let from = source.indexOf(delimiters[0]); from >= 0;) {
      const end = source.indexOf(delimiters[1], from + delimiters[0].length);
      if (end < 0) {
        ranges.push({from, to: source.length});
        break;
      }
      ranges.push({from, to: end + delimiters[1].length});
      from = source.indexOf(delimiters[0], end + delimiters[1].length);
    }
  }

  for (let cursor = 0; cursor < source.length;) {
    if (source.charCodeAt(cursor) !== 0x60) {
      cursor += 1;
      continue;
    }
    const from = cursor;
    while (cursor < source.length && source.charCodeAt(cursor) === 0x60) cursor += 1;
    const length = cursor - from;
    if (isEscaped(source, from)) continue;
    for (let search = cursor; search < source.length;) {
      if (source.charCodeAt(search) !== 0x60) {
        search += 1;
        continue;
      }
      const close = search;
      while (search < source.length && source.charCodeAt(search) === 0x60) search += 1;
      if (search - close === length) {
        ranges.push({from, to: search});
        cursor = search;
        break;
      }
    }
  }
  return ranges;
}

function intersects(range: Range, candidates: Range[]): boolean {
  return candidates.some((candidate) => candidate.from < range.to && range.from < candidate.to);
}

function isEscaped(source: string, position: number): boolean {
  let count = 0;
  for (let cursor = position - 1; cursor >= 0 && source.charCodeAt(cursor) === 0x5c; cursor -= 1) count += 1;
  return count % 2 === 1;
}

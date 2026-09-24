export interface LinkAnnotationRange {
  from: number;
  to: number;
  contentFrom: number;
  contentTo: number;
  markdown: string;
}

function isEscaped(source: string, position: number) {
  let backslashes = 0;
  for (let cursor = position - 1; cursor >= 0 && source.charCodeAt(cursor) === 0x5c; cursor -= 1) {
    backslashes += 1;
  }
  return backslashes % 2 === 1;
}

function hasVisibleMarkdownContent(markdown: string) {
  let remaining = markdown.replace(/(`+)[\s]*\1/g, "");
  remaining = remaining
    .replace(/^[ \t]{0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/gm, "")
    .replace(/^[ \t]{0,3}(?:#{1,6}|>+|[-+*]|\d+[.)])[ \t]*$/gm, "");
  return remaining.trim().length > 0;
}

/**
 * Finds the one valid source-owned annotation immediately following a
 * Wikilink. Invalid or unclosed markup remains ordinary exact source.
 */
export function linkAnnotationAfter(source: string, linkTo: number): LinkAnnotationRange | null {
  if (source.slice(linkTo, linkTo + 2) !== "{{") return null;
  for (let cursor = linkTo + 2; cursor + 1 < source.length; cursor += 1) {
    const pair = source.slice(cursor, cursor + 2);
    if (pair === "{{" && !isEscaped(source, cursor)) return null;
    if (pair !== "}}" || isEscaped(source, cursor)) continue;
    const markdown = source.slice(linkTo + 2, cursor);
    if (!hasVisibleMarkdownContent(markdown)) return null;
    return {
      from: linkTo,
      to: cursor + 2,
      contentFrom: linkTo + 2,
      contentTo: cursor,
      markdown,
    };
  }
  return null;
}

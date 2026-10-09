import {Text} from "@codemirror/state";
import {SearchCursor} from "@codemirror/search";

export interface DocumentFindMatch {from: number; to: number}
interface FindOptions {query: string; caseSensitive: boolean; wholeWord: boolean}

/** Shared word edges include authored combining marks and full code points. */
export function documentFindWordBoundary(doc: Text, from: number, to: number) {
  const before = (position: number) => /[\p{L}\p{N}\p{M}_]$/u.test(
    doc.sliceString(Math.max(0, position - 2), position));
  const after = (position: number) => /^[\p{L}\p{N}\p{M}_]/u.test(
    doc.sliceString(position, Math.min(doc.length, position + 2)));
  return (!before(from) || !after(from)) && (!after(to) || !before(to));
}

/** Plain rendered text needs the pinned search cursor, without an editor or
 * its history, command, and panel extensions. The cursor owns normalization. */
export function documentFindMatches(source: string, request: FindOptions): DocumentFindMatch[] {
  if (!request.query) return [];
  const doc = Text.of(source.split("\n"));
  const cursor = new SearchCursor(doc, request.query, 0, doc.length,
    request.caseSensitive ? undefined : value => value.toLowerCase(),
    request.wholeWord ? (from, to) => documentFindWordBoundary(doc, from, to) : undefined);
  const matches: DocumentFindMatch[] = [];
  for (let next = cursor.next(); !next.done; next = cursor.next()) {
    matches.push({from: next.value.from, to: next.value.to});
  }
  return matches;
}

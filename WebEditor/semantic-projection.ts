import type {EditorState, Text} from "@codemirror/state";
import {syntaxTree} from "@codemirror/language";

export interface SemanticProjectionRanges {
  headingLevelByLineFrom: Map<number, number>;
  paragraphs: Array<{from: number; to: number}>;
  strong: Set<string>;
  emphasis: Set<string>;
  links: Set<string>;
  wikilinks: Set<string>;
  strikethrough: Set<string>;
  highlights: Set<string>;
  tables: Array<{from: number; to: number}>;
  callouts: Array<{from: number; to: number}>;
}

export function rangeKey(from: number, to: number) {
  return `${from}:${to}`;
}

/**
 * Returns only the syntax-bearing start of the physical line containing
 * `position`. Interaction reporting must never materialize an arbitrarily
 * long `Line.text` merely to recognize a short block marker.
 */
export function boundedLinePrefix(doc: Text, position: number, limit = 512) {
  const line = doc.lineAt(Math.max(0, Math.min(position, doc.length)));
  return doc.sliceString(line.from, Math.min(line.to, line.from + limit));
}

export function boundedProjectionRanges(
  documentLength: number,
  visibleRanges: readonly {from: number; to: number}[],
  margin = 2_000,
) {
  const expanded = visibleRanges.map((range) => ({
    from: Math.max(0, range.from - margin),
    to: Math.min(documentLength, range.to + margin),
  })).sort((left, right) => left.from - right.from || left.to - right.to);
  const merged: Array<{from: number; to: number}> = [];
  for (const range of expanded) {
    const previous = merged.at(-1);
    if (previous && range.from <= previous.to) previous.to = Math.max(previous.to, range.to);
    else merged.push({...range});
  }
  return merged;
}

export function semanticProjectionRanges(
  state: EditorState,
  visibleRanges: readonly {from: number; to: number}[],
  margin = 2_000,
  tree: ReturnType<typeof syntaxTree> = syntaxTree(state),
): SemanticProjectionRanges {
  const result: SemanticProjectionRanges = {
    headingLevelByLineFrom: new Map(),
    paragraphs: [],
    strong: new Set(),
    emphasis: new Set(),
    links: new Set(),
    wikilinks: new Set(),
    strikethrough: new Set(),
    highlights: new Set(),
    tables: [],
    callouts: [],
  };
  if (visibleRanges.length === 0) return result;
  const from = Math.max(0, Math.min(...visibleRanges.map((range) => range.from)) - margin);
  const to = Math.min(state.doc.length, Math.max(...visibleRanges.map((range) => range.to)) + margin);
  tree.iterate({
    from,
    to,
    enter(node) {
      const heading = /^ATXHeading([1-6])$/.exec(node.name);
      if (heading) result.headingLevelByLineFrom.set(state.doc.lineAt(node.from).from, Number(heading[1]));
      if (node.name === "Paragraph") result.paragraphs.push({from: node.from, to: node.to});
      const key = rangeKey(node.from, node.to);
      if (node.name === "StrongEmphasis") result.strong.add(key);
      if (node.name === "Emphasis") result.emphasis.add(key);
      if (["Link", "Autolink"].includes(node.name)) result.links.add(key);
      if (["WikiLink", "VectorLink"].includes(node.name)) result.wikilinks.add(key);
      if (node.name === "Strikethrough") result.strikethrough.add(key);
      if (node.name === "Highlight") result.highlights.add(key);
      if (node.name === "Table") result.tables.push({from: node.from, to: node.to});
      if (node.name === "Callout") result.callouts.push({from: node.from, to: node.to});
    },
  });
  return result;
}

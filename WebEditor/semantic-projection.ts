import type {EditorState} from "@codemirror/state";
import {syntaxTree} from "@codemirror/language";

export interface SemanticProjectionRanges {
  headingLevelByLineFrom: Map<number, number>;
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

export function semanticProjectionRanges(
  state: EditorState,
  visibleRanges: readonly {from: number; to: number}[],
  margin = 2_000,
  tree: ReturnType<typeof syntaxTree> = syntaxTree(state),
): SemanticProjectionRanges {
  const result: SemanticProjectionRanges = {
    headingLevelByLineFrom: new Map(),
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

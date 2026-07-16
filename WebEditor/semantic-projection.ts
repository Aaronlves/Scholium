import type {EditorState} from "@codemirror/state";
import {syntaxTree} from "@codemirror/language";

export interface SemanticProjectionRanges {
  headingLevelByLineFrom: Map<number, number>;
  strong: Set<string>;
  emphasis: Set<string>;
  links: Set<string>;
  strikethrough: Set<string>;
  tables: Array<{from: number; to: number}>;
}

export function rangeKey(from: number, to: number) {
  return `${from}:${to}`;
}

export function semanticProjectionRanges(
  state: EditorState,
  visibleRanges: readonly {from: number; to: number}[],
  margin = 2_000,
): SemanticProjectionRanges {
  const result: SemanticProjectionRanges = {
    headingLevelByLineFrom: new Map(),
    strong: new Set(),
    emphasis: new Set(),
    links: new Set(),
    strikethrough: new Set(),
    tables: [],
  };
  if (visibleRanges.length === 0) return result;
  const from = Math.max(0, Math.min(...visibleRanges.map((range) => range.from)) - margin);
  const to = Math.min(state.doc.length, Math.max(...visibleRanges.map((range) => range.to)) + margin);
  syntaxTree(state).iterate({
    from,
    to,
    enter(node) {
      const heading = /^ATXHeading([1-6])$/.exec(node.name);
      if (heading) result.headingLevelByLineFrom.set(state.doc.lineAt(node.from).from, Number(heading[1]));
      const key = rangeKey(node.from, node.to);
      if (node.name === "StrongEmphasis") result.strong.add(key);
      if (node.name === "Emphasis") result.emphasis.add(key);
      if (["Link", "Autolink"].includes(node.name)) result.links.add(key);
      if (node.name === "Strikethrough") result.strikethrough.add(key);
      if (node.name === "Table") result.tables.push({from: node.from, to: node.to});
    },
  });
  return result;
}

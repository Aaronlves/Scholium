import type {SelectionRange} from "./protocol";
import type {SourceChange, Transformation} from "./transformations";

function lineBounds(source: string, offset: number) {
  const from = source.lastIndexOf("\n", Math.max(0, offset - 1)) + 1;
  const newline = source.indexOf("\n", offset);
  return {from, to: newline < 0 ? source.length : newline};
}

function listPrefix(line: string) {
  return /^(\s*)(?:(- \[[ xX]\] )|(- |\* |\+ )|(\d+)([.)] ))/.exec(line);
}

export function continueList(source: string, selections: SelectionRange[]): Transformation | null {
  if (selections.some((selection) => selection.anchor !== selection.head)) return null;
  const entries = selections.map((selection) => {
    const bounds = lineBounds(source, selection.head);
    const line = source.slice(bounds.from, bounds.to);
    const match = listPrefix(line);
    if (!match) return null;
    const prefix = match[0];
    const content = line.slice(prefix.length);
    if (content.trim().length === 0) {
      return {change: {from: bounds.from, to: bounds.from + prefix.length, insert: ""}, localSelection: bounds.from};
    }
    const ordered = match[4] ? `${Number(match[4]) + 1}${match[5]}` : null;
    const continued = `${match[1]}${ordered ?? (match[2] ? "- [ ] " : match[3])}`;
    return {change: {from: selection.head, to: selection.head, insert: `\n${continued}`}, localSelection: selection.head + 1 + continued.length};
  });
  if (entries.some((entry) => entry === null)) return null;
  const accepted = entries as NonNullable<(typeof entries)[number]>[];
  const sorted = [...accepted].sort((left, right) => left.change.from - right.change.from);
  let shift = 0;
  const mapped = sorted.map((entry) => {
    const position = entry.localSelection + shift;
    shift += entry.change.insert.length - (entry.change.to - entry.change.from);
    return {anchor: position, head: position};
  });
  return {changes: sorted.map((entry) => entry.change), selections: mapped, undoLabel: "Continue List"};
}

export function indentList(source: string, selections: SelectionRange[], backwards: boolean): Transformation | null {
  const lineStarts = [...new Set(selections.flatMap((selection) => {
    const first = lineBounds(source, Math.min(selection.anchor, selection.head));
    const last = lineBounds(source, Math.max(selection.anchor, selection.head));
    const starts: number[] = [];
    let cursor = first.from;
    while (cursor <= last.from) {
      starts.push(cursor);
      const next = source.indexOf("\n", cursor);
      if (next < 0) break;
      cursor = next + 1;
    }
    return starts;
  }))].sort((left, right) => left - right);
  const changes: SourceChange[] = [];
  for (const from of lineStarts) {
    const bounds = lineBounds(source, from);
    const line = source.slice(bounds.from, bounds.to);
    if (!listPrefix(line)) return null;
    if (backwards) {
      const indentation = /^\s*/.exec(line)?.[0] ?? "";
      if (indentation.length === 0) return null;
      changes.push({from, to: from + Math.min(2, indentation.length), insert: ""});
    } else changes.push({from, to: from, insert: "  "});
  }
  const positionAfterChanges = (position: number) => changes.reduce((mapped, change) => {
    if (change.from > position) return mapped;
    return mapped + change.insert.length - (change.to - change.from);
  }, position);
  return {
    changes,
    selections: selections.map((selection) => ({anchor: positionAfterChanges(selection.anchor), head: positionAfterChanges(selection.head)})),
    undoLabel: backwards ? "Outdent List" : "Indent List",
  };
}

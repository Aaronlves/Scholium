import type {SelectionRange} from "./protocol";
import type {SourceChange, Transformation} from "./transformations";
import {Text} from "@codemirror/state";

type InteractionSource = string | Text;

function interactionDocument(source: InteractionSource) {
  return typeof source === "string" ? Text.of(source.split("\n")) : source;
}

function listPrefix(line: string) {
  return /^(\s*)(?:(- \[[ xX]\] )|(- |\* |\+ )|(\d+)([.)] ))/.exec(line);
}

export function continueList(source: InteractionSource, selections: SelectionRange[]): Transformation | null {
  const document = interactionDocument(source);
  if (selections.some((selection) => selection.anchor !== selection.head)) return null;
  const entries = selections.map((selection) => {
    const bounds = document.lineAt(selection.head);
    const line = bounds.text;
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

export function indentList(
  source: InteractionSource,
  selections: SelectionRange[],
  backwards: boolean,
): Transformation | null {
  const document = interactionDocument(source);
  const lineStarts = [...new Set(selections.flatMap((selection) => {
    const first = document.lineAt(Math.min(selection.anchor, selection.head));
    const last = document.lineAt(Math.max(selection.anchor, selection.head));
    const starts: number[] = [];
    for (let number = first.number; number <= last.number; number += 1) {
      starts.push(document.line(number).from);
    }
    return starts;
  }))].sort((left, right) => left - right);
  const changes: SourceChange[] = [];
  for (const from of lineStarts) {
    const line = document.lineAt(from).text;
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

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

function continuedListPrefix(match: RegExpExecArray) {
  const ordered = match[4] ? `${Number(match[4]) + 1}${match[5]}` : null;
  return `${match[1]}${ordered ?? (match[2] ? "- [ ] " : match[3])}`;
}

function calloutQuotePrefix(line: string) {
  return /^(\s*>[ \t]?)/.exec(line);
}

function lineBelongsToCallout(document: Text, lineNumber: number) {
  for (let number = lineNumber; number >= 1; number -= 1) {
    const line = document.line(number).text;
    if (!calloutQuotePrefix(line)) return false;
    if (/^\s*>[ \t]*\[![^\]\r\n]+\](?:[+-])?(?:[ \t]|$)/.test(line)) return true;
  }
  return false;
}

/**
 * Continues the exact quote prefix inside a semantic Callout. Pressing Return
 * on the resulting empty quoted line removes that prefix and exits the block,
 * matching the ordinary two-Return Markdown authoring path.
 */
export function continueCallout(
  source: InteractionSource,
  selections: SelectionRange[],
): Transformation | null {
  const document = interactionDocument(source);
  if (selections.some((selection) => selection.anchor !== selection.head)) return null;
  const entries = selections.map((selection) => {
    const bounds = document.lineAt(selection.head);
    const prefix = calloutQuotePrefix(bounds.text)?.[1];
    if (!prefix || !lineBelongsToCallout(document, bounds.number)) return null;
    const quotedContent = bounds.text.slice(prefix.length);
    const nestedList = listPrefix(quotedContent);
    if (nestedList && quotedContent.slice(nestedList[0].length).trim().length === 0) {
      return {
        change: {
          from: bounds.from + prefix.length,
          to: bounds.from + prefix.length + nestedList[0].length,
          insert: "",
        },
        localSelection: bounds.from + prefix.length,
        undoLabel: "Exit List",
      };
    }
    if (quotedContent.trim().length === 0) {
      return {
        change: {from: bounds.from, to: bounds.from + prefix.length, insert: ""},
        localSelection: bounds.from,
        undoLabel: "Exit Callout",
      };
    }
    const continuedPrefix = nestedList
      ? `${prefix}${continuedListPrefix(nestedList)}`
      : prefix;
    return {
      change: {from: selection.head, to: selection.head, insert: `\n${continuedPrefix}`},
      localSelection: selection.head + 1 + continuedPrefix.length,
      undoLabel: nestedList ? "Continue List" : "Continue Callout",
    };
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
  return {
    changes: sorted.map((entry) => entry.change),
    selections: mapped,
    undoLabel: accepted.every((entry) => entry.undoLabel === accepted[0].undoLabel)
      ? accepted[0].undoLabel
      : "Continue Callout",
  };
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
    const continued = continuedListPrefix(match);
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

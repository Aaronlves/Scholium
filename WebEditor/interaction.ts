import type {SelectionRange} from "./protocol";
import type {SourceChange, Transformation} from "./transformations";
import {Text} from "@codemirror/state";

type InteractionSource = string | Text;
type InteractionLine = {
  readonly number: number;
  readonly from: number;
  readonly to: number;
  readonly text: string;
};

interface InteractionOptions {
  readonly lineIsProtected?: (line: InteractionLine) => boolean;
}

function interactionDocument(source: InteractionSource) {
  return typeof source === "string" ? Text.of(source.split("\n")) : source;
}

interface ListPrefix {
  readonly quotePrefix: string;
  readonly indentation: string;
  readonly marker: string;
  readonly orderedNumber: number | null;
  readonly orderedSuffix: string | null;
  readonly task: boolean;
  readonly sourcePrefix: string;
}

function blockquotePrefix(line: string) {
  let position = 0;
  while (position < line.length) {
    const match = /^[ \t]{0,3}>[ \t]?/.exec(line.slice(position));
    if (!match) break;
    position += match[0].length;
  }
  return line.slice(0, position);
}

function listPrefix(line: string): ListPrefix | null {
  const quotePrefix = blockquotePrefix(line);
  const remainder = line.slice(quotePrefix.length);
  // Keep the whole authored marker track, including the whitespace that
  // separates a marker from its body. Empty items are valid Markdown too, so
  // the separator is optional only at end-of-line. This lets Return remove a
  // bare `-`/`1.` item cleanly and keeps task-list variants on their own
  // bullet/numbering style when a new item is continued.
  const match = /^([ \t]*)([-*+]|(\d{1,9})([.)]))(?:([ \t]+)(\[[ xX]\])?([ \t]*)|$)/.exec(remainder);
  if (!match) return null;
  return {
    quotePrefix,
    indentation: match[1],
    marker: match[2],
    orderedNumber: match[3] ? Number(match[3]) : null,
    orderedSuffix: match[4] ?? null,
    task: match[6] !== undefined,
    sourcePrefix: `${quotePrefix}${match[0]}`,
  };
}

function continuedListPrefix(match: ListPrefix) {
  const ordered = match.orderedNumber === null || match.orderedSuffix === null
    ? null
    : `${match.orderedNumber + 1}${match.orderedSuffix}`;
  return `${match.quotePrefix}${match.indentation}${ordered ?? match.marker}${match.task ? " [ ] " : " "}`;
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
  options: InteractionOptions = {},
): Transformation | null {
  const document = interactionDocument(source);
  if (selections.some((selection) => selection.anchor !== selection.head)) return null;
  const entries = selections.map((selection) => {
    const bounds = document.lineAt(selection.head);
    if (options.lineIsProtected?.(bounds)) return null;
    const prefix = calloutQuotePrefix(bounds.text)?.[1];
    if (!prefix || !lineBelongsToCallout(document, bounds.number)) return null;
    const quotedContent = bounds.text.slice(prefix.length);
    const nestedList = listPrefix(quotedContent);
    if (nestedList && quotedContent.slice(nestedList.sourcePrefix.length).trim().length === 0) {
      return {
        change: {
          from: bounds.from + prefix.length,
          to: bounds.from + prefix.length + nestedList.sourcePrefix.length,
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

export function continueList(
  source: InteractionSource,
  selections: SelectionRange[],
  options: InteractionOptions = {},
): Transformation | null {
  const document = interactionDocument(source);
  if (selections.some((selection) => selection.anchor !== selection.head)) return null;
  const entries = selections.map((selection) => {
    const bounds = document.lineAt(selection.head);
    const line = bounds.text;
    const match = listPrefix(line);
    if (!match || options.lineIsProtected?.(bounds)) return null;
    const content = line.slice(match.sourcePrefix.length);
    if (content.trim().length === 0) {
      const from = bounds.from + match.quotePrefix.length;
      return {
        change: {from, to: bounds.from + match.sourcePrefix.length, insert: ""},
        localSelection: from,
      };
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
  options: InteractionOptions = {},
): Transformation | null {
  const document = interactionDocument(source);
  const lineStarts = [...new Set(selections.flatMap((selection) => {
    const start = Math.min(selection.anchor, selection.head);
    const end = Math.max(selection.anchor, selection.head);
    const first = document.lineAt(start);
    // A selection ending exactly at the next line's start does not select that
    // empty line. This matches CodeMirror's selected-line commands and keeps
    // Shift-Tab from touching a line the researcher did not include.
    const lastPosition = end > start && document.lineAt(end).from === end
      ? Math.max(start, end - 1)
      : end;
    const last = document.lineAt(lastPosition);
    const starts: number[] = [];
    for (let number = first.number; number <= last.number; number += 1) {
      starts.push(document.line(number).from);
    }
    return starts;
  }))].sort((left, right) => left - right);
  const changes: SourceChange[] = [];
  for (const from of lineStarts) {
    const bounds = document.lineAt(from);
    const match = listPrefix(bounds.text);
    if (!match || options.lineIsProtected?.(bounds)) return null;
    const indentationFrom = from + match.quotePrefix.length;
    if (backwards) {
      // A mixed-depth selection can contain both root items and nested items.
      // Mature editors leave root items in place while outdenting the lines
      // that still have one indentation unit available.
      if (match.indentation.length === 0) continue;
      const removeLength = match.indentation.startsWith("\t")
        ? 1
        : Math.min(2, match.indentation.length);
      changes.push({
        from: indentationFrom,
        to: indentationFrom + removeLength,
        insert: "",
      });
    } else changes.push({from: indentationFrom, to: indentationFrom, insert: "  "});
  }
  const positionAfterChanges = (position: number) => {
    let shift = 0;
    for (const change of changes) {
      if (position < change.from) return position + shift;
      if (position <= change.to) return change.from + shift + change.insert.length;
      shift += change.insert.length - (change.to - change.from);
    }
    return position + shift;
  };
  if (changes.length === 0) return null;
  return {
    changes,
    selections: selections.map((selection) => ({anchor: positionAfterChanges(selection.anchor), head: positionAfterChanges(selection.head)})),
    undoLabel: backwards ? "Outdent List" : "Indent List",
  };
}

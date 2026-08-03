import type {MarkdownEditorCommand, SelectionRange} from "./protocol";
import {transformTableCommand} from "./tables";

export interface SourceChange { from: number; to: number; insert: string }
export interface Transformation {
  changes: SourceChange[];
  selections: SelectionRange[];
  undoLabel: string;
}
export interface TransformOptions {
  argument?: string;
  protectedRanges?: readonly {from: number; to: number}[];
  taskItems?: readonly {
    from: number;
    to: number;
    markerFrom: number;
    markerTo: number;
  }[];
}

export function toggledTaskMarker(marker: string): "[x]" | "[ ]" | null {
  const match = /^\[([ xX])\]$/.exec(marker);
  if (!match) return null;
  return match[1] === " " ? "[x]" : "[ ]";
}

const inlineMarkers: Partial<Record<MarkdownEditorCommand, [string, string, string]>> = {
  bold: ["**", "**", "Bold"],
  emphasis: ["*", "*", "Italic"],
  strikethrough: ["~~", "~~", "Strikethrough"],
  highlight: ["==", "==", "Highlight"],
  markdownComment: ["%% ", " %%", "Markdown Comment"],
  wikilink: ["[[", "]]", "Wikilink"],
  vectorSupports: ["+[[", "]]", "Supports Link"],
  vectorOpposes: ["-[[", "]]", "Opposes Link"],
  vectorIncompatible: ["?[[", "]]", "Incompatible Link"],
};

function normalized(range: SelectionRange) {
  return {from: Math.min(range.anchor, range.head), to: Math.max(range.anchor, range.head)};
}
function overlaps(left: {from: number; to: number}, right: {from: number; to: number}) {
  if (left.from === left.to) return left.from >= right.from && left.from <= right.to;
  return left.from < right.to && left.to > right.from;
}
function lineBounds(source: string, range: {from: number; to: number}) {
  const from = source.lastIndexOf("\n", Math.max(0, range.from - 1)) + 1;
  const newline = source.indexOf("\n", range.to);
  return {from, to: newline < 0 ? source.length : newline};
}
function maximumRun(text: string, character: string) {
  let maximum = 0;
  for (const match of text.matchAll(new RegExp(`\\${character}+`, "g"))) maximum = Math.max(maximum, match[0].length);
  return maximum;
}
function labelFor(command: MarkdownEditorCommand) {
  return command.replace(/([A-Z])/g, " $1").replace(/^./, (value) => value.toUpperCase());
}

function inlineChange(
  source: string,
  range: {from: number; to: number},
  opening: string,
  closing: string,
): {change: SourceChange; selection: SelectionRange} {
  const selected = source.slice(range.from, range.to);
  const escapedOpening = range.from > 0 && source[range.from - 1] === "\\";
  if (!escapedOpening && selected.startsWith(opening) && selected.endsWith(closing)
      && selected.length >= opening.length + closing.length) {
    const insert = selected.slice(opening.length, selected.length - closing.length);
    return {change: {...range, insert}, selection: {anchor: range.from, head: range.from + insert.length}};
  }
  const enclosingFrom = range.from - opening.length;
  const escapedEnclosing = enclosingFrom > 0 && source[enclosingFrom - 1] === "\\";
  if (!escapedEnclosing && source.slice(enclosingFrom, range.from) === opening
      && source.slice(range.to, range.to + closing.length) === closing) {
    return {
      change: {from: range.from - opening.length, to: range.to + closing.length, insert: selected},
      selection: {anchor: range.from - opening.length, head: range.to - opening.length},
    };
  }
  const insert = `${opening}${selected}${closing}`;
  const anchor = range.from + opening.length;
  return {
    change: {...range, insert},
    selection: {anchor, head: anchor + selected.length},
  };
}

function transformOne(
  source: string,
  range: {from: number; to: number},
  command: MarkdownEditorCommand,
  argument?: string,
): {change: SourceChange; selection: SelectionRange; label: string} | null {
  const marker = inlineMarkers[command];
  if (marker) {
    const result = inlineChange(source, range, marker[0], marker[1]);
    return {...result, label: marker[2]};
  }
  if (command === "inlineCode") {
    const selected = source.slice(range.from, range.to);
    const fence = "`".repeat(Math.max(1, maximumRun(selected, "`") + 1));
    const result = inlineChange(source, range, fence, fence);
    return {...result, label: "Inline Code"};
  }
  if (command === "standardLink" || command === "linkSelectedText") {
    const selected = source.slice(range.from, range.to);
    const destination = argument ?? "";
    const insert = `[${selected}](${destination})`;
    const anchor = selected ? range.from + selected.length + 3 : range.from + 1;
    const head = selected ? anchor + destination.length : anchor;
    return {change: {...range, insert}, selection: {anchor, head}, label: "Link"};
  }
  if (command === "pastePlain" || command === "pasteMarkdown") {
    const insert = argument ?? "";
    return {change: {...range, insert}, selection: {anchor: range.from + insert.length, head: range.from + insert.length}, label: "Paste"};
  }
  if (command === "fencedCode") {
    const selected = source.slice(range.from, range.to);
    const fence = "`".repeat(Math.max(3, maximumRun(selected, "`") + 1));
    const insert = `${fence}\n${selected}\n${fence}`;
    return {
      change: {...range, insert},
      selection: {anchor: range.from + fence.length + 1, head: range.from + fence.length + 1 + selected.length},
      label: "Fenced Code",
    };
  }
  if (command === "thematicBreak") {
    return {change: {...range, insert: "---"}, selection: {anchor: range.from + 3, head: range.from + 3}, label: "Thematic Break"};
  }
  if (command === "insertTable") {
    const insert = "| Column 1 | Column 2 |\n|---|---|\n|  |  |";
    return {change: {...range, insert}, selection: {anchor: range.from + 2, head: range.from + 10}, label: "Insert Table"};
  }

  const bounds = lineBounds(source, range);
  const block = source.slice(bounds.from, bounds.to);
  const heading = /^ {0,3}#{1,6}[ \t]+/.exec(block);
  if (command === "paragraph" || /^heading[1-6]$/.test(command)) {
    const level = command === "paragraph" ? 0 : Number(command.slice(-1));
    const without = heading ? block.slice(heading[0].length) : block;
    const insert = level ? `${"#".repeat(level)} ${without}` : without;
    return {change: {...bounds, insert}, selection: {anchor: bounds.from + (level ? level + 1 : 0), head: bounds.from + insert.length}, label: level ? `Heading ${level}` : "Paragraph"};
  }
  const prefixByCommand: Partial<Record<MarkdownEditorCommand, string>> = {
    blockQuotation: "> ", bulletList: "- ", numberedList: "1. ", taskList: "- [ ] ",
    calloutOrient: "> [!orient] ", calloutCite: "> [!cite] ", calloutConnect: "> [!connect] ",
    calloutState: "> [!state] ", calloutIllustrate: "> [!illustrate] ",
    calloutQuote: "> [!quote] ", calloutFlag: "> [!flag] ",
  };
  const prefix = prefixByCommand[command];
  if (prefix !== undefined) {
    const insert = block.split("\n").map((line, index) => index === 0 || !prefix.startsWith("> [!") ? `${prefix}${line}` : `> ${line}`).join("\n");
    return {change: {...bounds, insert}, selection: {anchor: bounds.from + prefix.length, head: bounds.from + insert.length}, label: labelFor(command)};
  }
  return null;
}

export function transformMarkdown(
  source: string,
  selections: SelectionRange[],
  command: MarkdownEditorCommand,
  options: TransformOptions = {},
): Transformation | null {
  if (new TextEncoder().encode(source).byteLength > 8_000_000 || selections.length === 0) return null;
  const ranges = selections.map(normalized).sort((left, right) => left.from - right.from || left.to - right.to);
  if (ranges.some((range, index) => index > 0 && range.from < ranges[index - 1].to)) return null;
  if (ranges.some((range) => options.protectedRanges?.some((protectedRange) => overlaps(range, protectedRange)))) return null;

  const tableTransformation = transformTableCommand(source, selections, command);
  if (tableTransformation) return tableTransformation;

  if (command === "insertFootnote") {
    const used = new Set(Array.from(source.matchAll(/\[\^(\d+)\]/g), (match) => Number(match[1])));
    const allocated: number[] = [];
    let candidate = 1;
    for (const _range of ranges) {
      while (used.has(candidate)) candidate += 1;
      allocated.push(candidate);
      used.add(candidate);
      candidate += 1;
    }
    const referenceChanges = ranges.map((range, index) => ({
      from: range.from,
      to: range.to,
      insert: `[^${allocated[index]}]`,
    }));
    const bodyLength = source.length + referenceChanges.reduce(
      (total, change) => total + change.insert.length - (change.to - change.from), 0,
    );
    const separator = source.length === 0 ? "" : source.endsWith("\n") ? "\n" : "\n\n";
    let definitions = separator;
    const definitionSelections: SelectionRange[] = [];
    for (let index = 0; index < ranges.length; index += 1) {
      const content = options.argument ?? source.slice(ranges[index].from, ranges[index].to);
      const prefix = `[^${allocated[index]}]: `;
      const anchor = bodyLength + definitions.length + prefix.length;
      definitions += `${prefix}${content}\n`;
      definitionSelections.push({anchor, head: anchor + content.length});
    }
    return {
      changes: [...referenceChanges, {from: source.length, to: source.length, insert: definitions}],
      selections: definitionSelections,
      undoLabel: "Insert Footnote",
    };
  }

  if (command === "toggleTask") {
    const taskChanges = ranges.map((range) => {
      const bounds = lineBounds(source, range);
      const indexedItem = options.taskItems?.findLast((item) =>
        range.from >= item.from && range.to <= item.to);
      const fallback = options.taskItems === undefined
        ? /^([ \t]*(?:(?:[-+*])|(?:\d{1,9}[.)]))[ \t]+)(\[[ xX]\])/.exec(
            source.slice(bounds.from, bounds.to),
          )
        : null;
      const markerFrom = indexedItem?.markerFrom
        ?? (fallback ? bounds.from + fallback[1].length : null);
      const markerTo = indexedItem?.markerTo ?? (markerFrom === null ? null : markerFrom + 3);
      if (markerFrom === null || markerTo === null) return null;
      const insert = toggledTaskMarker(source.slice(markerFrom, markerTo));
      return insert === null ? null : {from: markerFrom, to: markerTo, insert};
    });
    if (taskChanges.some((change) => change === null)) return null;
    const uniqueChanges = new Map<string, SourceChange>();
    for (const change of taskChanges as SourceChange[]) {
      uniqueChanges.set(`${change.from}:${change.to}`, change);
    }
    const changes = [...uniqueChanges.values()]
      .sort((left, right) => left.from - right.from || left.to - right.to);
    if (changes.some((change, index) =>
      index > 0 && change.from < changes[index - 1].to)) return null;
    return {
      changes,
      selections,
      undoLabel: "Toggle Task",
    };
  }

  const transformed = ranges.map((range) => transformOne(source, range, command, options.argument));
  if (transformed.some((value) => value === null)) return null;
  const values = transformed as NonNullable<(typeof transformed)[number]>[];
  const changes = values.map((value) => value.change);
  const orderedChanges = [...changes].sort((left, right) => left.from - right.from || left.to - right.to);
  if (orderedChanges.some((change, index) => index > 0 && change.from < orderedChanges[index - 1].to)) return null;
  let shift = 0;
  const resultSelections = values.map((value) => {
    const selection = {anchor: value.selection.anchor + shift, head: value.selection.head + shift};
    shift += value.change.insert.length - (value.change.to - value.change.from);
    return selection;
  });
  return {changes, selections: resultSelections, undoLabel: values[0].label};
}

export function applySourceChanges(source: string, changes: SourceChange[]): string {
  let result = source;
  for (const change of [...changes].sort((left, right) => right.from - left.from)) {
    result = result.slice(0, change.from) + change.insert + result.slice(change.to);
  }
  return result;
}

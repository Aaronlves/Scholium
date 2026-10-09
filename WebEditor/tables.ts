import type {MarkdownEditorCommand, SelectionRange} from "./protocol";
import {ChangeSet, EditorSelection, Text} from "@codemirror/state";

export interface TableSourceChange { from: number; to: number; insert: string }
export interface TableTransformation {
  changes: TableSourceChange[];
  selections: SelectionRange[];
  undoLabel: string;
}
export interface ParsedTableCell { from: number; to: number; contentFrom: number; contentTo: number }
export interface ParsedTableRow { lineFrom: number; lineTo: number; cells: ParsedTableCell[] }
export interface ParsedTable {
  rows: ParsedTableRow[];
  separatorIndex: number;
  position: {row: number; column: number; rowCount: number; columnCount: number};
}

const tableCommands = new Set<MarkdownEditorCommand>([
  "tableInsertRowBefore", "tableInsertRowAfter", "tableDeleteRow",
  "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
  "tableAlignLeft", "tableAlignCenter", "tableAlignRight",
]);

type TableSource = string | Text;

function tableDocument(source: TableSource) {
  return typeof source === "string" ? Text.of(source.split("\n")) : source;
}

function unescapedPipes(line: string) {
  const positions: number[] = [];
  for (let index = 0; index < line.length; index += 1) {
    if (line[index] !== "|") continue;
    let slashCount = 0;
    for (let cursor = index - 1; cursor >= 0 && line[cursor] === "\\"; cursor -= 1) slashCount += 1;
    if (slashCount % 2 === 0) positions.push(index);
  }
  return positions;
}

function parseRow(source: Text, from: number, to: number): ParsedTableRow | null {
  const line = source.sliceString(from, to);
  const pipes = unescapedPipes(line);
  if (pipes.length === 0) return null;
  const firstContent = line.search(/\S/);
  const lastContent = line.search(/\s*$/) - 1;
  const hasLeading = firstContent >= 0 && pipes[0] === firstContent;
  const hasTrailing = lastContent >= 0 && pipes[pipes.length - 1] === lastContent;
  const boundaries = [hasLeading ? pipes[0] : -1, ...pipes.slice(hasLeading ? 1 : 0, hasTrailing ? -1 : undefined), hasTrailing ? pipes[pipes.length - 1] : line.length];
  const cells: ParsedTableCell[] = [];
  for (let index = 0; index < boundaries.length - 1; index += 1) {
    const rawFrom = boundaries[index] + 1;
    const rawTo = boundaries[index + 1];
    if (rawTo < rawFrom) return null;
    const raw = line.slice(rawFrom, rawTo);
    const leading = raw.match(/^\s*/)?.[0].length ?? 0;
    const trailing = raw.match(/\s*$/)?.[0].length ?? 0;
    cells.push({
      from: from + rawFrom,
      to: from + rawTo,
      contentFrom: from + rawFrom + leading,
      contentTo: from + Math.max(rawFrom + leading, rawTo - trailing),
    });
  }
  return cells.length >= 1 ? {lineFrom: from, lineTo: to, cells} : null;
}

function isSeparatorCell(source: Text, cell: ParsedTableCell) {
  return /^:?-{3,}:?$/.test(source.sliceString(cell.contentFrom, cell.contentTo));
}

function rowNumber(table: ParsedTable, rawRow: number) {
  return rawRow > table.separatorIndex ? rawRow - 1 : rawRow;
}

export function tableAt(source: TableSource, offset: number): ParsedTable | null {
  const document = tableDocument(source);
  if (offset < 0 || offset > document.length) return null;
  const current = document.lineAt(offset);
  let firstLineNumber = current.number;
  while (firstLineNumber > 1) {
    const previous = document.line(firstLineNumber - 1);
    if (!parseRow(document, previous.from, previous.to)) break;
    firstLineNumber -= 1;
  }
  const rows: ParsedTableRow[] = [];
  for (let number = firstLineNumber; number <= document.lines; number += 1) {
    const line = document.line(number);
    const row = parseRow(document, line.from, line.to);
    if (!row) break;
    rows.push(row);
  }
  if (rows.length < 2) return null;
  const columnCount = rows[0].cells.length;
  if (rows.some((row) => row.cells.length !== columnCount)) return null;
  const separators = rows.flatMap((row, index) =>
    row.cells.every((cell) => isSeparatorCell(document, cell)) ? [index] : []);
  if (separators.length !== 1 || separators[0] !== 1) return null;
  const rawRow = rows.findIndex((row) => offset >= row.lineFrom && offset <= row.lineTo);
  if (rawRow < 0 || rawRow === separators[0]) return null;
  const column = rows[rawRow].cells.findIndex((cell, index) => {
    const next = rows[rawRow].cells[index + 1];
    return offset >= cell.from && offset <= (next ? next.from - 1 : cell.to);
  });
  if (column < 0) return null;
  const table: ParsedTable = {
    rows,
    separatorIndex: separators[0],
    position: {row: 0, column, rowCount: rows.length - 1, columnCount},
  };
  table.position.row = rowNumber(table, rawRow);
  return table;
}

function blankRow(columnCount: number) {
  return `|${Array.from({length: columnCount}, () => "  ").join("|")}|`;
}

function mappedTableSelections(source: string, changes: TableSourceChange[], selections: SelectionRange[]) {
  const changeSet = ChangeSet.of(changes, source.length);
  return selections.map(({anchor, head}) => {
    const mapped = EditorSelection.range(anchor, head).map(changeSet);
    return {anchor: mapped.anchor, head: mapped.head};
  });
}

export function tableCommandAvailable(command: string, position: ParsedTable["position"] | undefined): boolean {
  if (!position || !tableCommands.has(command as MarkdownEditorCommand)) return false;
  if (command === "tableInsertRowBefore") return position.row > 0;
  if (command === "tableDeleteRow") return position.row > 0 && position.rowCount > 2;
  if (command === "tableDeleteColumn") return position.columnCount > 1;
  return true;
}

export function transformTableCommand(
  source: string,
  selections: SelectionRange[],
  command: MarkdownEditorCommand,
): TableTransformation | null {
  if (!tableCommands.has(command) || selections.length !== 1) return null;
  const selection = selections[0];
  const table = tableAt(source, selection.head);
  if (!table || !tableCommandAvailable(command, table.position)) return null;
  const rawRow = table.position.row === 0 ? 0 : table.position.row + 1;
  const row = table.rows[rawRow];
  const column = table.position.column;

  if (command === "tableInsertRowBefore" || command === "tableInsertRowAfter") {
    const before = command === "tableInsertRowBefore";
    // A header must remain adjacent to its delimiter row. The first body row
    // is inserted below both source rows, never between them.
    const point = before ? row.lineFrom
      : table.position.row === 0 ? table.rows[table.separatorIndex].lineTo : row.lineTo;
    const insert = before ? `${blankRow(table.position.columnCount)}\n` : `\n${blankRow(table.position.columnCount)}`;
    const cellOffset = insert.indexOf("  ") + 1;
    return {changes: [{from: point, to: point, insert}], selections: [{anchor: point + cellOffset, head: point + cellOffset}], undoLabel: before ? "Insert Table Row Before" : "Insert Table Row After"};
  }
  if (command === "tableDeleteRow") {
    const hasFollowingNewline = row.lineTo < source.length;
    const from = hasFollowingNewline ? row.lineFrom : Math.max(0, row.lineFrom - 1);
    const to = hasFollowingNewline ? row.lineTo + 1 : row.lineTo;
    return {changes: [{from, to, insert: ""}], selections: [{anchor: from, head: from}], undoLabel: "Delete Table Row"};
  }
  if (command.startsWith("tableAlign")) {
    const separator = table.rows[table.separatorIndex].cells[column];
    const current = source.slice(separator.contentFrom, separator.contentTo);
    const dashes = "-".repeat(Math.max(3, current.replaceAll(":", "").length));
    const insert = command === "tableAlignLeft" ? `:${dashes}` : command === "tableAlignRight" ? `${dashes}:` : `:${dashes}:`;
    const changes = [{from: separator.contentFrom, to: separator.contentTo, insert}];
    return {changes, selections: mappedTableSelections(source, changes, selections), undoLabel: "Align Table Column"};
  }

  const inserting = command === "tableInsertColumnBefore" || command === "tableInsertColumnAfter";
  if (!inserting && command !== "tableDeleteColumn") return null;
  const changes: TableSourceChange[] = [];
  for (let index = 0; index < table.rows.length; index += 1) {
    const target = table.rows[index].cells[column];
    if (inserting) {
      const before = command === "tableInsertColumnBefore";
      const point = before ? target.from : target.to;
      const content = index === table.separatorIndex ? "---" : " ";
      changes.push({from: point, to: point, insert: before ? `${content} |` : `| ${content}`});
    } else {
      const next = table.rows[index].cells[column + 1];
      if (next) changes.push({from: target.from, to: next.from, insert: ""});
      else {
        const previous = table.rows[index].cells[column - 1];
        changes.push({from: previous.to, to: target.to, insert: ""});
      }
    }
  }
  return {changes, selections: mappedTableSelections(source, changes, selections), undoLabel: inserting ? "Insert Table Column" : "Delete Table Column"};
}

export function tableTabAction(
  source: TableSource,
  offset: number,
  backwards: boolean,
): TableTransformation | null {
  const table = tableAt(source, offset);
  if (!table) return null;
  const editableCells = table.rows.flatMap((row, rawRow) => rawRow === table.separatorIndex ? [] : row.cells);
  const currentIndex = editableCells.findIndex((cell) => offset >= cell.from && offset <= cell.to);
  if (currentIndex < 0) return null;
  const nextIndex = currentIndex + (backwards ? -1 : 1);
  if (nextIndex >= 0 && nextIndex < editableCells.length) {
    const next = editableCells[nextIndex];
    return {changes: [], selections: [{anchor: next.contentFrom, head: next.contentTo}], undoLabel: "Move Between Table Cells"};
  }
  if (backwards) return null;
  const final = table.rows[table.rows.length - 1];
  const insert = `\n${blankRow(table.position.columnCount)}`;
  const firstCell = final.lineTo + insert.indexOf("  ") + 1;
  return {changes: [{from: final.lineTo, to: final.lineTo, insert}], selections: [{anchor: firstCell, head: firstCell}], undoLabel: "Append Table Row"};
}

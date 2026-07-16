import type {MarkdownEditorCommand, SelectionRange} from "./protocol";

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

function lineRange(source: string, offset: number) {
  const from = source.lastIndexOf("\n", Math.max(0, offset - 1)) + 1;
  const newline = source.indexOf("\n", offset);
  return {from, to: newline < 0 ? source.length : newline};
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

function parseRow(source: string, from: number, to: number): ParsedTableRow | null {
  const line = source.slice(from, to);
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
  return cells.length >= 2 ? {lineFrom: from, lineTo: to, cells} : null;
}

function isSeparatorCell(source: string, cell: ParsedTableCell) {
  return /^:?-{3,}:?$/.test(source.slice(cell.contentFrom, cell.contentTo));
}

function rowNumber(table: ParsedTable, rawRow: number) {
  return rawRow > table.separatorIndex ? rawRow - 1 : rawRow;
}

export function tableAt(source: string, offset: number): ParsedTable | null {
  if (offset < 0 || offset > source.length) return null;
  const current = lineRange(source, offset);
  let first = current.from;
  while (first > 0) {
    const previous = lineRange(source, first - 1);
    if (!parseRow(source, previous.from, previous.to)) break;
    first = previous.from;
  }
  const rows: ParsedTableRow[] = [];
  let cursor = first;
  while (cursor <= source.length) {
    const line = lineRange(source, cursor);
    const row = parseRow(source, line.from, line.to);
    if (!row) break;
    rows.push(row);
    if (line.to === source.length) break;
    cursor = line.to + 1;
  }
  if (rows.length < 2) return null;
  const columnCount = rows[0].cells.length;
  if (rows.some((row) => row.cells.length !== columnCount)) return null;
  const separators = rows.flatMap((row, index) => row.cells.every((cell) => isSeparatorCell(source, cell)) ? [index] : []);
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

export function transformTableCommand(
  source: string,
  selections: SelectionRange[],
  command: MarkdownEditorCommand,
): TableTransformation | null {
  if (!tableCommands.has(command) || selections.length !== 1) return null;
  const selection = selections[0];
  const table = tableAt(source, selection.head);
  if (!table) return null;
  const rawRow = table.position.row === 0 ? 0 : table.position.row + 1;
  const row = table.rows[rawRow];
  const column = table.position.column;
  const cell = row.cells[column];

  if (command === "tableInsertRowBefore" || command === "tableInsertRowAfter") {
    const before = command === "tableInsertRowBefore";
    const point = before ? row.lineFrom : row.lineTo;
    const insert = before ? `${blankRow(table.position.columnCount)}\n` : `\n${blankRow(table.position.columnCount)}`;
    const cellOffset = insert.indexOf("  ") + 1;
    return {changes: [{from: point, to: point, insert}], selections: [{anchor: point + cellOffset, head: point + cellOffset}], undoLabel: before ? "Insert Table Row Before" : "Insert Table Row After"};
  }
  if (command === "tableDeleteRow") {
    if (table.position.row === 0 || table.position.rowCount <= 2) return null;
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
    return {changes: [{from: separator.contentFrom, to: separator.contentTo, insert}], selections, undoLabel: "Align Table Column"};
  }

  const inserting = command === "tableInsertColumnBefore" || command === "tableInsertColumnAfter";
  if (!inserting && command !== "tableDeleteColumn") return null;
  if (command === "tableDeleteColumn" && table.position.columnCount <= 2) return null;
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
  return {changes, selections, undoLabel: inserting ? "Insert Table Column" : "Delete Table Column"};
}

export function tableTabAction(source: string, offset: number, backwards: boolean): TableTransformation | null {
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

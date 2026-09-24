import {tableAt} from "./tables";

export type TableColumnAlignment = "left" | "center" | "right" | null;

export interface TablePresentationCell {
  source: string;
  sourceOffset: number;
  alignment: TableColumnAlignment;
}

export interface TablePresentation {
  from: number;
  to: number;
  source: string;
  header: TablePresentationCell[];
  body: TablePresentationCell[][];
}

function alignmentFor(separator: string): TableColumnAlignment {
  const value = separator.trim();
  if (value.startsWith(":") && value.endsWith(":")) return "center";
  if (value.endsWith(":")) return "right";
  if (value.startsWith(":")) return "left";
  return null;
}

function cellSource(source: string, from: number, to: number) {
  return source.slice(from, to).replaceAll("\\|", "|");
}

/**
 * Builds a display-only table projection from exact Markdown. Source offsets
 * remain the only editing identity; the projection is never serialized back.
 */
export function tablePresentation(
  source: string,
  from: number,
  to: number,
): TablePresentation | null {
  if (from < 0 || to <= from || to > source.length) return null;
  const parsed = tableAt(source, Math.min(to, from + 1));
  if (!parsed || parsed.rows[0].lineFrom !== from) return null;
  const finalRow = parsed.rows[parsed.rows.length - 1];
  if (finalRow.lineTo !== to) return null;

  const separator = parsed.rows[parsed.separatorIndex];
  const alignments = separator.cells.map((cell) =>
    alignmentFor(source.slice(cell.contentFrom, cell.contentTo))
  );
  const rows = parsed.rows
    .filter((_, index) => index !== parsed.separatorIndex)
    .map((row) => row.cells.map((cell, column) => ({
      source: cellSource(source, cell.contentFrom, cell.contentTo),
      sourceOffset: cell.contentFrom,
      alignment: alignments[column] ?? null,
    })));
  const header = rows.shift();
  if (!header) return null;
  return {
    from,
    to,
    source: source.slice(from, to),
    header,
    body: rows,
  };
}

import type {Text} from "@codemirror/state";
import type {SemanticCodeBlockRange} from "./live-projection-index";
import type {ProjectionSourceRange} from "./projection-update";

export interface MermaidPresentation extends ProjectionSourceRange {
  readonly source: string;
  readonly content: string;
  readonly contentFrom: number;
  readonly contentTo: number;
}

export function mermaidPresentation(
  doc: Text,
  block: SemanticCodeBlockRange,
): MermaidPresentation | null {
  if (!block.fenced || block.markerRanges.length < 2) return null;
  const opening = block.markerRanges[0];
  const closing = block.markerRanges.at(-1);
  if (!opening || !closing) return null;
  const openingLine = doc.lineAt(opening.from);
  const closingLine = doc.lineAt(closing.from);
  if (openingLine.from === closingLine.from) return null;
  const information = doc.sliceString(opening.to, openingLine.to).trim();
  if (information.split(/\s+/, 1)[0]?.toLowerCase() !== "mermaid") return null;
  const contentFrom = openingLine.number < doc.lines
    ? doc.line(openingLine.number + 1).from
    : openingLine.to;
  const contentTo = closingLine.from;
  return {
    from: block.from,
    to: block.to,
    source: doc.sliceString(block.from, block.to),
    content: doc.sliceString(contentFrom, contentTo).replace(/[\r\n]+$/, ""),
    contentFrom,
    contentTo,
  };
}

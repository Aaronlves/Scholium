import {Text} from "@codemirror/state";

/** Resolves a clicked link from the exact CodeMirror source line. */
export function linkTargetAt(source: string | Text, offset: number): string | null {
  const document = typeof source === "string" ? Text.of(source.split("\n")) : source;
  if (offset < 0 || offset > document.length) return null;
  const sourceLine = document.lineAt(offset);
  const lineFrom = sourceLine.from;
  const line = sourceLine.text;
  for (const match of line.matchAll(/!?\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g)) {
    const from = lineFrom + match.index;
    const to = from + match[0].length;
    if (offset >= from && offset < to) return match[1].trim();
  }
  for (const match of line.matchAll(/\[[^\]\n]+\]\(([^)\n]+)\)/g)) {
    const from = lineFrom + match.index;
    const to = from + match[0].length;
    if (offset >= from && offset < to) return match[1].trim();
  }
  return null;
}

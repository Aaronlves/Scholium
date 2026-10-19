import {Text} from "@codemirror/state";
import {scholiumMarkdownContentLanguage} from "./language";
import {isCitationDestination} from "./zotero-field-envelope";

/** Markdown's angle delimiters belong to source syntax, never the destination. */
export function markdownLinkDestination(source: string): string {
  return source.trim().replace(/^<([\s\S]*)>$/, "$1");
}

/** Resolves a clicked link from the exact CodeMirror source line. */
export function linkTargetAt(source: string | Text, offset: number): string | null {
  const document = typeof source === "string" ? Text.of(source.split("\n")) : source;
  if (offset < 0 || offset > document.length) return null;
  const sourceLine = document.lineAt(offset);
  const lineFrom = sourceLine.from;
  const line = sourceLine.text;
  const position = offset - lineFrom;
  let target: string | null = null;
  // Parse only the clicked line with the editor's existing language. A regular
  // expression cannot distinguish angle destinations, titles and parentheses.
  scholiumMarkdownContentLanguage.language.parser.parse(line).iterate({
    enter(node) {
      if (position < node.from || position >= node.to) return false;
      const child = node.name === "WikiLink" ? node.node.getChild("WikiLinkTarget")
        : node.name === "Link" || node.name === "Image" ? node.node.getChild("URL") : null;
      if (!child) return;
      const sourceTarget = line.slice(child.from, child.to);
      const destination = node.name === "WikiLink" ? sourceTarget.trim() : markdownLinkDestination(sourceTarget);
      target = isCitationDestination(destination) ? null : destination;
      return false;
    },
  });
  return target;
}

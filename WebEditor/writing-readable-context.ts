import type {EditorState} from "@codemirror/state";
import {ensureSyntaxTree, syntaxTreeAvailable} from "@codemirror/language";
import type {SyntaxNode} from "@lezer/common";
import {codeBlockActivationRange, type LiveProjectionIndex} from "./live-projection-index";
import {boundedLinePrefix, type SemanticSourceRange} from "./semantic-projection";

const markerNames = new Set([
  "HeaderMark", "QuoteMark", "ListMark", "TaskMarker", "TableDelimiter",
  "CalloutQuoteMark", "CalloutRoleMark", "FootnoteOpenMark", "FootnoteCloseMark",
  "FootnoteIdentifier", "FootnoteDefinitionMark", "InlineFootnoteOpenMark",
  "LinkMark", "LinkLabel", "URL", "LinkTitle", "WikiLinkOpenMark", "WikiEmbedMark",
  "WikiLinkAliasMark", "WikiLinkCloseMark", "WikiLinkTarget",
  "EmphasisMark", "StrikethroughMark", "HighlightMark", "CodeMark", "MathMark",
]);

const literalNames = new Set([
  "FencedCode", "CodeBlock", "InlineCode", "BlockMath", "UnclosedBlockMath",
  "InlineMath", "HTMLBlock", "HTMLTag", "CommentBlock", "Comment",
  "ObsidianComment", "UnclosedObsidianComment",
  "ObsidianCommentBlock", "UnclosedObsidianCommentBlock", "LinkReference", "Autolink",
]);

function contains(range: SemanticSourceRange, position: number) {
  return position >= range.from && position < range.to;
}

function readableBoundary(range: SemanticSourceRange, position: number) {
  return range.to > range.from && position >= range.from && position <= range.to;
}

function completeLinkLabel(node: SyntaxNode): SemanticSourceRange | null {
  const marks: SemanticSourceRange[] = [];
  let reference: SyntaxNode | null = null;
  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (child.name === "LinkMark") marks.push({from: child.from, to: child.to});
    if (child.name === "LinkLabel") reference = child;
  }
  // Recoverable [label](unfinished nodes end after the label. They cannot
  // authorize writing inside a destination that the parser has not proved.
  if (marks.length < 4 && (!reference || reference.to !== node.to)) return null;
  return marks.length >= 2 ? {from: marks[0].to, to: marks[1].from} : null;
}

/**
 * A nonauthorizing caret check in normalized CodeMirror UTF-16 coordinates.
 * The existing parser/catalog owns classification; native context capture and
 * suggestion acceptance still own exact source, selection and request currency.
 */
export function writingCaretIsReadable(
  state: EditorState,
  index: LiveProjectionIndex,
  position: number,
): boolean {
  if (!Number.isSafeInteger(position) || position < 0 || position > state.doc.length
      || index.hasUnclosedFrontmatter
      || (index.frontmatterRange && contains(index.frontmatterRange, position))
      || !syntaxTreeAvailable(state, Math.min(state.doc.length, position + 1))) return false;
  if (position > 0 && position < state.doc.length) {
    const adjacent = state.doc.sliceString(position - 1, position + 1);
    if (/^[\uD800-\uDBFF][\uDC00-\uDFFF]$/.test(adjacent)) return false;
  }
  if (index.literals.excluded.some(range => contains(range, position))
      || index.mathExpressions.some(range => contains(range, position))
      || index.referenceDefinitionRanges.some(range => readableBoundary(range, position))
      || index.literals.codeBlocks.some(block =>
        contains(codeBlockActivationRange(state.doc, block), position))) return false;

  // Availability proves the existing ParseContext is already complete here.
  // Read that same tree without parsing or dispatching: the published
  // LanguageState.tree can still lag the catalog built by ensureSyntaxTree.
  const tree = ensureSyntaxTree(state, Math.min(state.doc.length, position + 1), 0);
  if (!tree) return false;
  const line = state.doc.lineAt(position);
  // An unfinished reference definition can fall back to a plain paragraph.
  // Its authored definition prefix is still ambiguous structural input, while
  // named footnote definitions keep their independently parsed prose body.
  if (/^[ \t]{0,3}\[(?!\^)(?:\\.|[^\]\\\r\n])+\]:/.test(boundedLinePrefix(state.doc, position))) return false;
  const markers: SemanticSourceRange[] = [];
  const classified: SemanticSourceRange[] = [];
  const linkLabels: SemanticSourceRange[] = [];
  const cells: SemanticSourceRange[] = [];
  let forbidden = false;
  let tableWhitespaceBoundary = false;
  tree.iterate({
    from: line.from, to: line.to,
    enter(reference) {
      const node = reference.node;
      if (literalNames.has(node.name)) {
        if (contains(node, position)) forbidden = true;
        if (node.to <= position) classified.push({from: node.from, to: node.to});
      }
      if (markerNames.has(node.name)) {
        let to = node.to;
        if (["QuoteMark", "CalloutQuoteMark", "CalloutRoleMark"].includes(node.name)) {
          while (to < line.to && /[ \t]/.test(state.doc.sliceString(to, to + 1))) to++;
        }
        markers.push({from: node.from, to});
        classified.push({from: node.from, to});
      }
      if (node.name === "Escape") classified.push({from: node.from, to: node.to});
      if (node.name === "TableCell" || node.name === "FootnoteContent") {
        let end = node.to;
        if (node.name === "TableCell") {
          // Cell nodes omit horizontal padding. Inserting after authored text
          // and its spaces still belongs to this cell, even at the next pipe.
          while (end < line.to && /[ \t]/.test(state.doc.sliceString(end, end + 1))) end++;
          tableWhitespaceBoundary ||= end > node.to && position > node.to && position <= end;
        }
        cells.push({from: node.from, to: end});
      }
      if (node.name === "Link" || node.name === "Image") {
        const label = completeLinkLabel(node);
        if (label) {
          linkLabels.push(label);
          if (node.to <= position) classified.push({from: node.from, to: node.to});
        } else if (contains(node, position)
            || (node.from < position && /[([:]/.test(state.doc.sliceString(node.to, node.to + 1)))) {
          forbidden = true;
        }
      }
    },
  });
  if (forbidden) return false;

  let inlineEndIsReadable = linkLabels.some(range => readableBoundary(range, position));
  for (const inline of index.syntax.inlines) {
    if (inline.kind === "blockAnchor" && readableBoundary(inline, position)) return false;
    if (inline.to <= position) classified.push(inline);
    if (!contains(inline, position)) continue;
    if (["code", "inlineMath", "comment", "footnoteReference", "blockAnchor"].includes(inline.kind)
        || inline.nodeName === "Autolink") return false;
    const visible = inline.kind === "wikilink"
      ? [inline.aliasRange, inline.annotationContentRange].filter(
        (range): range is SemanticSourceRange => range !== null)
      : inline.visibleRanges;
    if (!visible.some(range => readableBoundary(range, position))) return false;
    inlineEndIsReadable ||= visible.some(range => position === range.to);
    classified.push(...inline.markerRanges);
    if (inline.targetRange) classified.push(inline.targetRange);
  }
  const cellEndIsReadable = cells.some(range => position === range.to && range.to > range.from);
  const structuralMarkers = [
    ...index.listPrefixRanges,
    ...index.syntax.blocks.flatMap(block => block.markerRanges),
  ];
  if (structuralMarkers.some(range => contains(range, position)) && !tableWhitespaceBoundary) return false;
  if (markers.some(range => contains(range, position))
      && !inlineEndIsReadable && !cellEndIsReadable) return false;
  const readable = inlineEndIsReadable || cells.some(range => readableBoundary(range, position))
    || index.syntax.blocks.some(block =>
      (block.kind === "paragraph" || block.kind === "heading") && readableBoundary(block, position));
  if (!readable) return false;

  // The parser deliberately leaves unfinished inline constructs as ordinary
  // source. Veto their unclassified opening characters instead of inventing a
  // fallback Markdown parse. Complete constructs and escaped literals are
  // skipped; a veto never changes source or the standard editing behavior.
  classified.sort((left, right) => left.from - right.from || right.to - left.to);
  let rangeIndex = 0;
  for (let cursor = line.from; cursor < position;) {
    while (rangeIndex < classified.length && classified[rangeIndex].to <= cursor) rangeIndex++;
    const known = classified[rangeIndex];
    if (known && known.from <= cursor) { cursor = Math.min(known.to, position); continue; }
    const character = state.doc.sliceString(cursor, cursor + 1);
    if (character === "\\") { cursor += 2; continue; }
    if (character === "[" || character === "`" || character === "$" || character === "<"
        || (character === "%" && state.doc.sliceString(cursor, cursor + 2) === "%%")) return false;
    cursor++;
  }
  return true;
}

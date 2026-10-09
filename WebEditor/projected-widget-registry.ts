import type {FootnoteReferencePresentation} from "./footnote-presentation";
import type {MermaidPresentation} from "./mermaid-presentation";
import type {TablePresentation} from "./table-presentation";
import {findClusterBreak} from "@codemirror/state";
import {renderedTextSourceOffset} from "./markdown-fragment";

function projectedSourceOffsetAt(
  event: MouseEvent,
  root: HTMLElement,
  fallback: number,
  upperBound: number,
) {
  const caretDocument = document as Document & {
    caretRangeFromPoint?: (x: number, y: number) => globalThis.Range | null;
  };
  const hit = caretDocument.caretRangeFromPoint?.(event.clientX, event.clientY) ?? null;
  const caret = hit && root.contains(hit.startContainer) ? hit : null;
  const caretElement = caret?.startContainer instanceof Element
    ? caret.startContainer
    : caret?.startContainer.parentElement;
  const pointMapped = document.elementsFromPoint(event.clientX, event.clientY)
    .flatMap((element) => {
      const candidate = element.closest<HTMLElement>("[data-source-offset]");
      return candidate && root.contains(candidate) ? [candidate] : [];
    })[0] ?? null;
  const mapped = caretElement?.closest<HTMLElement>("[data-source-offset]")
    ?? pointMapped
    ?? (event.target instanceof Element
      ? event.target.closest<HTMLElement>("[data-source-offset]")
      : null)
    ?? root;
  const base = Number(mapped.dataset.sourceOffset);
  if (!Number.isSafeInteger(base)) return fallback;
  if (caret) {
    const exact = renderedTextSourceOffset(caret.startContainer, caret.startOffset);
    if (exact !== null) return Math.max(fallback, Math.min(upperBound, exact));
  }
  let sourceOffset = base;
  if (mapped !== root || pointMapped) {
    const walker = document.createTreeWalker(mapped, NodeFilter.SHOW_TEXT);
    let bestScore = Number.POSITIVE_INFINITY;
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const content = node.textContent ?? "";
      for (let index = 0, end = 0; index < content.length; index = end) {
        end = findClusterBreak(content, index);
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, end);
        const rect = range.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) continue;
        const verticalDistance = event.clientY < rect.top
          ? rect.top - event.clientY
          : event.clientY > rect.bottom
            ? event.clientY - rect.bottom
            : 0;
        const horizontalDistance = event.clientX < rect.left
          ? rect.left - event.clientX
          : event.clientX > rect.right
            ? event.clientX - rect.right
            : 0;
        const score = verticalDistance * 1_000 + horizontalDistance;
        const offset = event.clientX > (rect.left + rect.right) / 2 ? end : index;
        const exact = renderedTextSourceOffset(node, offset);
        if (exact !== null && score < bestScore) {
          bestScore = score;
          sourceOffset = exact;
        }
      }
    }
  }
  return Math.max(fallback, Math.min(upperBound, sourceOffset));
}

export interface ProjectedWidgetRegistry {
  table(element: HTMLElement): TablePresentation | undefined;
  setTable(element: HTMLElement, value: TablePresentation): void;
  mermaid(element: HTMLElement): MermaidPresentation | undefined;
  setMermaid(element: HTMLElement, value: MermaidPresentation): void;
  footnote(element: HTMLElement): FootnoteReferencePresentation | undefined;
  setFootnote(element: HTMLElement, value: FootnoteReferencePresentation): void;
  sourceOffset(event: MouseEvent): number | null;
}

export function createProjectedWidgetRegistry(): ProjectedWidgetRegistry {
  const tables = new WeakMap<HTMLElement, TablePresentation>();
  const mermaids = new WeakMap<HTMLElement, MermaidPresentation>();
  const footnotes = new WeakMap<HTMLElement, FootnoteReferencePresentation>();

  return {
    table: (element) => tables.get(element),
    setTable: (element, value) => tables.set(element, value),
    mermaid: (element) => mermaids.get(element),
    setMermaid: (element, value) => mermaids.set(element, value),
    footnote: (element) => footnotes.get(element),
    setFootnote: (element, value) => footnotes.set(element, value),
    sourceOffset(event) {
      const target = event.target instanceof Element ? event.target : null;
      if (!target || target.closest(".scholium-callout-fold-mark")) return null;

      const projectedLink = target.closest<HTMLElement>("[data-scholium-source-caret]");
      const requestedLinkCaret = Number(projectedLink?.dataset.scholiumSourceCaret);
      if (Number.isSafeInteger(requestedLinkCaret)) return requestedLinkCaret;

      const table = target.closest<HTMLElement>(".cm-live-table-widget");
      const tablePresentation = table ? tables.get(table) : undefined;
      if (table && tablePresentation) {
        return projectedSourceOffsetAt(
          event,
          table,
          tablePresentation.from,
          tablePresentation.to,
        );
      }

      const mermaid = target.closest<HTMLElement>(".cm-live-mermaid-widget");
      const mermaidPresentation = mermaid ? mermaids.get(mermaid) : undefined;
      if (mermaidPresentation) return mermaidPresentation.contentFrom;

      const footnote = target.closest<HTMLElement>(".cm-live-footnote-reference-widget");
      const reference = footnote ? footnotes.get(footnote) : undefined;
      return reference?.definitionContentFrom ?? null;
    },
  };
}

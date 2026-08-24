import type {FootnoteReferencePresentation} from "./footnote-presentation";
import type {CalloutPresentation} from "./live-projection-index";
import type {MermaidPresentation} from "./mermaid-presentation";
import type {TablePresentation} from "./table-presentation";

function projectedSourceOffsetAt(
  event: MouseEvent,
  root: HTMLElement,
  fallback: number,
  upperBound: number,
) {
  const caretDocument = document as Document & {
    caretRangeFromPoint?: (x: number, y: number) => globalThis.Range | null;
  };
  const caret = caretDocument.caretRangeFromPoint?.(event.clientX, event.clientY) ?? null;
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
  let visibleOffset = 0;
  if (caret && mapped.contains(caret.startContainer)) {
    const range = document.createRange();
    range.setStart(mapped, 0);
    range.setEnd(caret.startContainer, caret.startOffset);
    visibleOffset = range.toString().length;
  } else if (mapped !== root || pointMapped) {
    const walker = document.createTreeWalker(mapped, NodeFilter.SHOW_TEXT);
    let textOffset = 0;
    let bestScore = Number.POSITIVE_INFINITY;
    let bestOffset = 0;
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const content = node.textContent ?? "";
      for (let index = 0; index < content.length; index += 1) {
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + 1);
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
        if (score < bestScore) {
          bestScore = score;
          bestOffset = textOffset + index + (event.clientX > (rect.left + rect.right) / 2 ? 1 : 0);
        }
      }
      textOffset += content.length;
    }
    visibleOffset = bestOffset;
  }
  return Math.max(fallback, Math.min(upperBound - 1, base + visibleOffset));
}

export interface ProjectedWidgetRegistry {
  table(element: HTMLElement): TablePresentation | undefined;
  setTable(element: HTMLElement, value: TablePresentation): void;
  mermaid(element: HTMLElement): MermaidPresentation | undefined;
  setMermaid(element: HTMLElement, value: MermaidPresentation): void;
  callout(element: HTMLElement): CalloutPresentation | undefined;
  setCallout(element: HTMLElement, value: CalloutPresentation): void;
  footnote(element: HTMLElement): FootnoteReferencePresentation | undefined;
  setFootnote(element: HTMLElement, value: FootnoteReferencePresentation): void;
  sourceOffset(event: MouseEvent): number | null;
}

export function createProjectedWidgetRegistry(): ProjectedWidgetRegistry {
  const tables = new WeakMap<HTMLElement, TablePresentation>();
  const mermaids = new WeakMap<HTMLElement, MermaidPresentation>();
  const callouts = new WeakMap<HTMLElement, CalloutPresentation>();
  const footnotes = new WeakMap<HTMLElement, FootnoteReferencePresentation>();

  return {
    table: (element) => tables.get(element),
    setTable: (element, value) => tables.set(element, value),
    mermaid: (element) => mermaids.get(element),
    setMermaid: (element, value) => mermaids.set(element, value),
    callout: (element) => callouts.get(element),
    setCallout: (element, value) => callouts.set(element, value),
    footnote: (element) => footnotes.get(element),
    setFootnote: (element, value) => footnotes.set(element, value),
    sourceOffset(event) {
      const target = event.target instanceof Element ? event.target : null;
      if (!target || target.closest(".scholium-callout-fold-mark")) return null;

      const projectedLink = target.closest<HTMLElement>("[data-scholium-source-caret]");
      const requestedLinkCaret = Number(projectedLink?.dataset.scholiumSourceCaret);
      if (Number.isSafeInteger(requestedLinkCaret)) return requestedLinkCaret;

      const calloutSlot = target.closest<HTMLElement>(".cm-live-callout-slot");
      const callout = calloutSlot ? callouts.get(calloutSlot) : undefined;
      if (callout) return callout.to;

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

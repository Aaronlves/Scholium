import {reviewRangeTextNodes} from "./review-selection-text";

interface SelectionPresentation {
  readonly supported: boolean;
  clear(): void;
  update(selection: Selection | null, main: HTMLElement | null): void;
  testingSnapshot?: () => Record<string, unknown>;
}

type HighlightRegistry = Map<string, Highlight> & {
  delete(name: string): boolean;
  has(name: string): boolean;
  set(name: string, highlight: Highlight): unknown;
};

function highlightRegistry(): HighlightRegistry | null {
  const value = (CSS as typeof CSS & {highlights?: HighlightRegistry}).highlights;
  return value ?? null;
}

export function createReviewSelectionPresentation(
  selectionEnabled: boolean,
  testingEnabled: boolean,
): SelectionPresentation {
  const registry = highlightRegistry();
  const supported = selectionEnabled
    && typeof Highlight === "function"
    && registry !== null;
  let textRanges: Range[] = [];
  const presentation: SelectionPresentation = {
    supported,
    clear() {
      const hadRanges = textRanges.length > 0;
      textRanges = [];
      if (supported && hadRanges) registry?.delete("scholium-review-selection");
    },
    update(selection, main) {
      this.clear();
      if (!supported || !main || !selection || selection.rangeCount !== 1
          || selection.isCollapsed) return;
      const sourceRange = selection.getRangeAt(0);
      if (!main.contains(sourceRange.startContainer)
          || !main.contains(sourceRange.endContainer)) return;
      for (const node of reviewRangeTextNodes(sourceRange, main)) {
        if (!node.textContent?.trim()
            || node.parentElement?.closest('[aria-hidden="true"], script, style')) continue;
        const from = sourceRange.startContainer === node ? sourceRange.startOffset : 0;
        const to = sourceRange.endContainer === node ? sourceRange.endOffset : node.length;
        if (from >= to) continue;
        const range = document.createRange();
        range.setStart(node, from);
        range.setEnd(node, to);
        textRanges.push(range);
      }
      if (textRanges.length && registry) {
        registry.set("scholium-review-selection", new Highlight(...textRanges));
      }
    },
  };

  if (testingEnabled) {
    presentation.testingSnapshot = () => {
      const selection = window.getSelection();
      const nativeRange = selection?.rangeCount ? selection.getRangeAt(0) : null;
      const rectangles = (range: Range | null) => range
        ? Array.from(range.getClientRects()).map((rect) => ({
          left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom,
          width: rect.width, height: rect.height,
        }))
        : [];
      const paragraph = document.querySelector("#scholium-document p");
      return {
        supported,
        selectedText: selection?.toString() ?? "",
        presentedText: textRanges.map((range) => range.toString()).join(""),
        nativeSelectionBackground: paragraph
          ? getComputedStyle(paragraph, "::selection").backgroundColor
          : "",
        nativeRectangles: rectangles(nativeRange),
        textRectangles: textRanges.flatMap((range) => rectangles(range)),
        textRangeCount: textRanges.length,
        customHighlightInstalled: supported
          && (registry?.has("scholium-review-selection") ?? false),
      };
    };
  }
  if (supported) document.documentElement.classList.add("scholium-review-custom-selection");
  return presentation;
}

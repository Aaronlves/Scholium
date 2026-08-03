import Foundation

/// Mirrors WebKit's authoritative Review selection into a text-only custom
/// highlight. This component owns paint only: native Selection remains the
/// copy, accessibility, Comment-range, and navigation authority.
enum ReviewSelectionPresentation {
    static var script: String {
        #if DEBUG
        let testingMembers = """
              testingSnapshot() {
                const selection = window.getSelection();
                const nativeRange = selection && selection.rangeCount ? selection.getRangeAt(0) : null;
                const rectangles = range => range
                  ? Array.from(range.getClientRects()).map(rect => ({
                      left: rect.left,
                      right: rect.right,
                      top: rect.top,
                      bottom: rect.bottom,
                      width: rect.width,
                      height: rect.height
                    }))
                  : [];
                return {
                  supported: this.supported,
                  selectedText: selection ? selection.toString() : '',
                  presentedText: reviewSelectionTextRanges.map(range => range.toString()).join(''),
                  nativeSelectionBackground: (() => {
                    const paragraph = document.querySelector('#scholium-document p');
                    return paragraph ? getComputedStyle(paragraph, '::selection').backgroundColor : '';
                  })(),
                  nativeRectangles: rectangles(nativeRange),
                  textRectangles: reviewSelectionTextRanges.flatMap(rectangles),
                  textRangeCount: reviewSelectionTextRanges.length,
                  customHighlightInstalled: this.supported
                    && CSS.highlights.has('scholium-review-selection')
                };
              },
        """
        #else
        let testingMembers = ""
        #endif

        return """
            const reviewSelectionSupported = selectionEnabled
              && typeof Highlight === 'function'
              && typeof CSS === 'object'
              && CSS !== null
              && 'highlights' in CSS;
            let reviewSelectionTextRanges = [];
            const reviewSelectionPresentation = {
              supported: reviewSelectionSupported,
              clear() {
                const hadRanges = reviewSelectionTextRanges.length > 0;
                reviewSelectionTextRanges = [];
                if (this.supported && hadRanges) CSS.highlights.delete('scholium-review-selection');
              },
              update(selection, main, textNodesInRange) {
                this.clear();
                if (!this.supported
                    || !main
                    || !selection
                    || selection.rangeCount !== 1
                    || selection.isCollapsed
                    || typeof textNodesInRange !== 'function') return;
                const sourceRange = selection.getRangeAt(0);
                if (!main.contains(sourceRange.startContainer) || !main.contains(sourceRange.endContainer)) return;
                for (const node of textNodesInRange(sourceRange, main)) {
                  if (!node.textContent?.trim() || node.parentElement?.closest('[aria-hidden="true"], script, style')) continue;
                  const from = sourceRange.startContainer === node ? sourceRange.startOffset : 0;
                  const to = sourceRange.endContainer === node ? sourceRange.endOffset : node.length;
                  if (from >= to) continue;
                  const textRange = document.createRange();
                  textRange.setStart(node, from);
                  textRange.setEnd(node, to);
                  reviewSelectionTextRanges.push(textRange);
                }
                if (reviewSelectionTextRanges.length) {
                  CSS.highlights.set(
                    'scholium-review-selection',
                    new Highlight(...reviewSelectionTextRanges)
                  );
                }
              },
        \(testingMembers)
            };
            window.scholiumReviewSelection = reviewSelectionPresentation;
            if (reviewSelectionSupported) {
              document.documentElement.classList.add('scholium-review-custom-selection');
            }
        """
    }

    static let css = """
        html.scholium-review-custom-selection #scholium-document::selection,
        html.scholium-review-custom-selection #scholium-document ::selection {
          color: inherit;
          background-color: transparent;
        }
        ::highlight(scholium-review-selection) {
          background-color: color-mix(in srgb, var(--scholium-color-accent) 24%, transparent);
        }
    """
}

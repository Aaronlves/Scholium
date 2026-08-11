import Foundation

extension SafeMarkdownReadWebView {
    static let reviewFindScript = #"""
    (() => {
      const allHighlightName = 'scholium-review-find';
      const currentHighlightName = 'scholium-review-find-current';
      let signature = '';
      let matches = [];
      let current = -1;

      const style = document.createElement('style');
      style.textContent = `
        ::highlight(scholium-review-find) {
          background: color-mix(in srgb, var(--scholium-color-accent) 22%, transparent);
        }
        ::highlight(scholium-review-find-current) {
          background: color-mix(in srgb, var(--scholium-color-accent) 42%, transparent);
          text-decoration: underline;
          text-decoration-color: var(--scholium-color-accent);
        }
      `;
      document.head.appendChild(style);

      function clearHighlights() {
        if (CSS.highlights) {
          CSS.highlights.delete(allHighlightName);
          CSS.highlights.delete(currentHighlightName);
        }
      }

      function searchableLines() {
        const root = document.querySelector('main');
        if (!root) return [];
        const sourceLines = [...root.querySelectorAll('[data-source-line]')]
          .filter(element => !element.querySelector('[data-source-line]'));
        return sourceLines.length > 0 ? sourceLines : [root];
      }

      function textNodesIn(element) {
        const nodes = [];
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, {
          acceptNode(node) {
            const parent = node.parentElement;
            if (!parent || !node.data) return NodeFilter.FILTER_REJECT;
            if (parent.closest('script, style, [hidden], [aria-hidden="true"], #selection-actions, #scholium-preview-popover')) {
              return NodeFilter.FILTER_REJECT;
            }
            if (parent.closest('[data-scholium-protected="mermaid"]')) {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        while (walker.nextNode()) nodes.push(walker.currentNode);
        return nodes;
      }

      function rangeFor(nodes, start, end) {
        let offset = 0;
        let startNode = null;
        let startOffset = 0;
        let endNode = null;
        let endOffset = 0;
        for (const node of nodes) {
          const next = offset + node.data.length;
          if (!startNode && start >= offset && start <= next) {
            startNode = node;
            startOffset = start - offset;
          }
          if (endNode === null && end >= offset && end <= next) {
            endNode = node;
            endOffset = end - offset;
            break;
          }
          offset = next;
        }
        if (!startNode || !endNode) return null;
        const range = new Range();
        range.setStart(startNode, startOffset);
        range.setEnd(endNode, endOffset);
        return range;
      }

      function isWord(character) {
        return Boolean(character) && /[\p{L}\p{N}_]/u.test(character);
      }

      function rangesFor(request) {
        if (!request.query) return [];
        const collator = request.caseSensitive
          ? null
          : new Intl.Collator(undefined, {usage: 'search', sensitivity: 'accent'});
        const result = [];
        for (const line of searchableLines()) {
          const nodes = textNodesIn(line);
          const text = nodes.map(node => node.data).join('');
          for (let index = 0; index <= text.length - request.query.length;) {
            const candidate = text.slice(index, index + request.query.length);
            const equal = request.caseSensitive
              ? candidate === request.query
              : collator.compare(candidate, request.query) === 0;
            const whole = !request.wholeWord
              || (!isWord(text[index - 1]) && !isWord(text[index + request.query.length]));
            if (equal && whole) {
              const range = rangeFor(nodes, index, index + request.query.length);
              if (range) result.push(range);
              index += Math.max(1, request.query.length);
            } else {
              index += 1;
            }
          }
        }
        return result;
      }

      function present() {
        clearHighlights();
        if (matches.length === 0 || !CSS.highlights) return;
        const ordinary = matches.filter((_, index) => index !== current);
        if (ordinary.length > 0) {
          CSS.highlights.set(allHighlightName, new Highlight(...ordinary));
        }
        CSS.highlights.set(currentHighlightName, new Highlight(matches[current]));
        const container = matches[current].startContainer.parentElement;
        container?.scrollIntoView({block: 'center', behavior: 'auto'});
      }

      window.scholiumReviewFind = {
        perform(request) {
          if (!request || request.operation === 'clear') {
            signature = '';
            matches = [];
            current = -1;
            clearHighlights();
            return {current: 0, total: 0};
          }
          const nextSignature = JSON.stringify([
            request.query, request.caseSensitive, request.wholeWord
          ]);
          if (nextSignature !== signature || request.action === 'update') {
            signature = nextSignature;
            matches = rangesFor(request);
            current = matches.length > 0 ? 0 : -1;
          } else if (request.action === 'next' && matches.length > 0) {
            current = (current + 1) % matches.length;
          } else if (request.action === 'previous' && matches.length > 0) {
            current = (current - 1 + matches.length) % matches.length;
          }
          present();
          return {current: current < 0 ? 0 : current + 1, total: matches.length};
        }
      };
    })();
    """#
}

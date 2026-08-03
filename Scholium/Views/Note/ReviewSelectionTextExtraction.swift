import Foundation

/// Traverses only the Review DOM region adjacent to a native Selection.
/// It owns bounded transient text extraction; Markdown, selection, Comment
/// authority, and selection paint remain with their existing owners.
enum ReviewSelectionTextExtraction {
    static let script = #"""
        const reviewNodeAfterSubtree = (node, root) => {
          let current = node;
          while (current && current !== root) {
            if (current.nextSibling) return current.nextSibling;
            current = current.parentNode;
          }
          return null;
        };
        const nextReviewNode = (node, root) =>
          node.firstChild || reviewNodeAfterSubtree(node, root);
        const previousReviewNode = (node, root) => {
          if (!node || node === root) return null;
          if (node.previousSibling) {
            let previous = node.previousSibling;
            while (previous.lastChild) previous = previous.lastChild;
            return previous;
          }
          return node.parentNode === root ? root : node.parentNode;
        };
        const reviewBoundaryNode = (container, offset, root) => {
          if (container instanceof Text) return container;
          return container.childNodes?.[offset] || reviewNodeAfterSubtree(container, root);
        };
        const reviewRangeTextNodes = function* (range, root) {
          let node = reviewBoundaryNode(range.startContainer, range.startOffset, root);
          const stop = range.endContainer instanceof Text
            ? nextReviewNode(range.endContainer, root)
            : reviewBoundaryNode(range.endContainer, range.endOffset, root);
          while (node && node !== stop) {
            if (node instanceof Text) {
              try {
                if (range.intersectsNode(node)) yield node;
              } catch (_) { /* Ignore a detached transient node. */ }
            }
            node = nextReviewNode(node, root);
          }
        };
        const boundedReviewRangeText = (range, root, limit) => {
          let result = '';
          let started = false;
          let nonWhitespaceAfterLimit = false;
          for (const node of reviewRangeTextNodes(range, root)) {
            const from = range.startContainer === node ? range.startOffset : 0;
            const to = range.endContainer === node ? range.endOffset : node.length;
            let chunk = node.data.slice(from, to);
            if (!started) {
              const firstContent = chunk.search(/\S/u);
              if (firstContent < 0) continue;
              chunk = chunk.slice(firstContent);
              started = true;
            }
            const remaining = Math.max(0, limit - result.length);
            if (remaining > 0) result += chunk.slice(0, remaining);
            if (/\S/u.test(chunk.slice(remaining))) {
              nonWhitespaceAfterLimit = true;
              if (result.length >= limit) break;
            }
          }
          return nonWhitespaceAfterLimit ? result : result.trimEnd();
        };
        const reviewContextBefore = (range, root, limit) => {
          const chunks = [];
          let remaining = limit;
          let node = range.startContainer;
          if (node instanceof Text) {
            const prefix = node.data.slice(0, range.startOffset);
            const chunk = prefix.slice(-remaining);
            if (chunk) {
              chunks.push(chunk);
              remaining -= chunk.length;
            }
            node = previousReviewNode(node, root);
          } else if (range.startOffset > 0) {
            node = node.childNodes[range.startOffset - 1] || previousReviewNode(node, root);
            while (node?.lastChild) node = node.lastChild;
          } else {
            node = previousReviewNode(node, root);
          }
          while (node && node !== root && remaining > 0) {
            if (node instanceof Text) {
              const chunk = node.data.slice(-remaining);
              if (chunk) {
                chunks.push(chunk);
                remaining -= chunk.length;
              }
            }
            node = previousReviewNode(node, root);
          }
          return chunks.reverse().join('');
        };
        const reviewContextAfter = (range, root, limit) => {
          const chunks = [];
          let remaining = limit;
          let node;
          if (range.endContainer instanceof Text) {
            const suffix = range.endContainer.data.slice(range.endOffset);
            const chunk = suffix.slice(0, remaining);
            if (chunk) {
              chunks.push(chunk);
              remaining -= chunk.length;
            }
            node = nextReviewNode(range.endContainer, root);
          } else {
            node = reviewBoundaryNode(range.endContainer, range.endOffset, root);
          }
          while (node && remaining > 0) {
            if (node instanceof Text) {
              const chunk = node.data.slice(0, remaining);
              if (chunk) {
                chunks.push(chunk);
                remaining -= chunk.length;
              }
            }
            node = nextReviewNode(node, root);
          }
          return chunks.join('');
        };
        """#
}

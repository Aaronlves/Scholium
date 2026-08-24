function nodeAfterSubtree(node: Node, root: Node): Node | null {
  let current: Node | null = node;
  while (current && current !== root) {
    if (current.nextSibling) return current.nextSibling;
    current = current.parentNode;
  }
  return null;
}

function nextNode(node: Node, root: Node): Node | null {
  return node.firstChild || nodeAfterSubtree(node, root);
}

function previousNode(node: Node | null, root: Node): Node | null {
  if (!node || node === root) return null;
  if (node.previousSibling) {
    let previous = node.previousSibling;
    while (previous.lastChild) previous = previous.lastChild;
    return previous;
  }
  return node.parentNode === root ? root : node.parentNode;
}

function boundaryNode(container: Node, offset: number, root: Node): Node | null {
  if (container instanceof Text) return container;
  return container.childNodes[offset] || nodeAfterSubtree(container, root);
}

export function* reviewRangeTextNodes(range: Range, root: Node): Generator<Text> {
  let node = boundaryNode(range.startContainer, range.startOffset, root);
  const stop = range.endContainer instanceof Text
    ? nextNode(range.endContainer, root)
    : boundaryNode(range.endContainer, range.endOffset, root);
  while (node && node !== stop) {
    if (node instanceof Text) {
      try {
        if (range.intersectsNode(node)) yield node;
      } catch {
        // A transient projected node may detach during selection delivery.
      }
    }
    node = nextNode(node, root);
  }
}

export function boundedReviewRangeText(
  range: Range,
  root: Node,
  limit: number,
): string {
  let result = "";
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
}

export function reviewContextBefore(range: Range, root: Node, limit: number): string {
  const chunks: string[] = [];
  let remaining = limit;
  let node: Node | null = range.startContainer;
  if (node instanceof Text) {
    const chunk = node.data.slice(0, range.startOffset).slice(-remaining);
    if (chunk) {
      chunks.push(chunk);
      remaining -= chunk.length;
    }
    node = previousNode(node, root);
  } else if (range.startOffset > 0) {
    node = node.childNodes[range.startOffset - 1] || previousNode(node, root);
    while (node?.lastChild) node = node.lastChild;
  } else {
    node = previousNode(node, root);
  }
  while (node && node !== root && remaining > 0) {
    if (node instanceof Text) {
      const chunk = node.data.slice(-remaining);
      if (chunk) {
        chunks.push(chunk);
        remaining -= chunk.length;
      }
    }
    node = previousNode(node, root);
  }
  return chunks.reverse().join("");
}

export function reviewContextAfter(range: Range, root: Node, limit: number): string {
  const chunks: string[] = [];
  let remaining = limit;
  let node: Node | null;
  if (range.endContainer instanceof Text) {
    const chunk = range.endContainer.data.slice(range.endOffset, range.endOffset + remaining);
    if (chunk) {
      chunks.push(chunk);
      remaining -= chunk.length;
    }
    node = nextNode(range.endContainer, root);
  } else {
    node = boundaryNode(range.endContainer, range.endOffset, root);
  }
  while (node && remaining > 0) {
    if (node instanceof Text) {
      const chunk = node.data.slice(0, remaining);
      if (chunk) {
        chunks.push(chunk);
        remaining -= chunk.length;
      }
    }
    node = nextNode(node, root);
  }
  return chunks.join("");
}

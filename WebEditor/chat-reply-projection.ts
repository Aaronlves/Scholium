/** Reconcile native-sanitized reply blocks, retaining already decorated blocks.
 * This is a read projection only; no DOM state is returned as Markdown. */
export function createReplyProjection(root: HTMLElement) {
  let sourceNodes = [...root.childNodes].map(node => node.cloneNode(true));
  let renderedNodes = [...root.childNodes];
  const commit = () => { renderedNodes = [...root.childNodes]; };

  function patch(current: Node, previous: Node, next: Node): Node {
    if (previous.isEqualNode(next)) return current;
    if (current.nodeType === 3 && next.nodeType === 3) {
      const text = current as Text;
      const value = next.textContent || '';
      let prefix = 0;
      while (prefix < text.length && prefix < value.length && text.data[prefix] === value[prefix]) prefix++;
      // replaceData preserves live Range endpoints before the edited suffix.
      text.replaceData(prefix, text.length - prefix, value.slice(prefix));
      return current;
    }
    // Only reconcile undecorated markup. Math, diagrams and object controls
    // are owned by the reader and rebuilt only when their source block changes.
    if (current.nodeType === 1 && next.nodeType === 1 && current.isEqualNode(previous)
        && (current as Element).tagName === (next as Element).tagName) {
      const element = current as Element;
      for (const attribute of [...element.attributes]) element.removeAttribute(attribute.name);
      for (const attribute of [...(next as Element).attributes]) element.setAttribute(attribute.name, attribute.value);
      const oldChildren = [...previous.childNodes];
      const children = [...current.childNodes];
      [...next.childNodes].forEach((child, index) => {
        const updated = children[index] ? patch(children[index], oldChildren[index], child) : child.cloneNode(true);
        if (!children[index]) current.appendChild(updated);
        else if (updated !== children[index]) current.replaceChild(updated, children[index]);
      });
      children.slice(next.childNodes.length).forEach(child => child.parentNode?.removeChild(child));
      return current;
    }
    return next.cloneNode(true);
  }

  function apply(html: string) {
    const selection = root.ownerDocument.defaultView?.getSelection();
    const range = selection?.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0) : null;
    const selected = range && root.contains(range.commonAncestorContainer) ? range.toString() : '';
    let offset = 0;
    let backward = false;
    if (selected && range && selection) {
      const before = range.cloneRange();
      before.selectNodeContents(root); before.setEnd(range.startContainer, range.startOffset);
      offset = before.toString().length;
      backward = selection.anchorNode === range.endContainer && selection.anchorOffset === range.endOffset;
    }
    const template = root.ownerDocument.createElement('template');
    template.innerHTML = html;
    const nextNodes = [...template.content.childNodes];
    nextNodes.forEach((next, index) => {
      const current = renderedNodes[index];
      const updated = current ? patch(current, sourceNodes[index], next) : next.cloneNode(true);
      if (!current) root.appendChild(updated);
      else if (updated !== current) root.replaceChild(updated, current);
    });
    renderedNodes.slice(nextNodes.length).forEach(node => node.parentNode?.removeChild(node));
    sourceNodes = nextNodes.map(node => node.cloneNode(true));
    commit();
    // Inline Markdown can acquire markup when its closing delimiter arrives.
    // Restore only the exact selected text; never select a different passage.
    return () => {
      if (!selected || !selection || selection.toString() === selected) return;
      const text = root.textContent || '';
      if (text.slice(offset, offset + selected.length) !== selected) {
        const candidate = text.indexOf(selected);
        if (candidate < 0 || text.indexOf(selected, candidate + 1) >= 0) return;
        offset = candidate;
      }
      const walker = root.ownerDocument.createTreeWalker(root, 4);
      let position = 0;
      let start: [Node, number] | undefined;
      let end: [Node, number] | undefined;
      while (walker.nextNode()) {
        const node = walker.currentNode as Text;
        if (!start && position + node.length >= offset) start = [node, offset - position];
        if (position + node.length >= offset + selected.length) { end = [node, offset + selected.length - position]; break; }
        position += node.length;
      }
      if (start && end) selection.setBaseAndExtent(...(backward ? end : start), ...(backward ? start : end));
    };
  }
  return {apply, commit};
}

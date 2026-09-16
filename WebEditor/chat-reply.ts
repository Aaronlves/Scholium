/** One DOM selection spans reply prose and locally scrolling rich objects. */
export function installChatReply(
  root: HTMLElement,
  post: (type: string, value: Record<string, unknown>) => void,
  localized: (key: string) => string,
) {
  const quote = () => {
    const selection = window.getSelection();
    if (!selection?.rangeCount || selection.isCollapsed
        || !root.contains(selection.anchorNode) || !root.contains(selection.focusNode)) return;
    const text = selection.toString();
    if (text.trim() && new TextEncoder().encode(text).length <= 65_536) post('replyQuote', {text});
  };
  const keydown = (event: KeyboardEvent) => {
    if (event.metaKey && event.shiftKey && !event.altKey && !event.ctrlKey && event.key.toLowerCase() === 'r') {
      event.preventDefault(); quote();
    }
  };
  const noteContextMenu = (event: MouseEvent) => {
    const selection = window.getSelection();
    if (selection?.rangeCount && !selection.isCollapsed
        && root.contains(selection.anchorNode) && root.contains(selection.focusNode)
        && [...selection.getRangeAt(0).getClientRects()].some(rect =>
          event.clientX >= rect.left && event.clientX <= rect.right
          && event.clientY >= rect.top && event.clientY <= rect.bottom)) {
      const text = selection.toString();
      if (text.trim() && new TextEncoder().encode(text).length <= 65_536) {
        event.preventDefault();
        event.stopPropagation();
        post('replySelectionContext', {text, left: event.clientX, top: event.clientY});
        return;
      }
    }
    const anchor = event.target instanceof Element ? event.target.closest<HTMLAnchorElement>('a[href]') : null;
    if (!anchor || !root.contains(anchor) || anchor.protocol !== 'scholium-note:') return;
    // SafeMarkdownRenderer wraps internal targets in an encoded navigation URL.
    // Use the same target decoding as the reader's ordinary link-click route.
    let url: string;
    try { url = decodeURIComponent((anchor.getAttribute('href') || '').slice('scholium-note:'.length)); }
    catch { return; }
    if (!url.startsWith('scholium-note://')) return;
    event.preventDefault();
    event.stopPropagation();
    post('replyNoteContext', {url, left: event.clientX, top: event.clientY});
  };
  const interact = () => post('replyInteraction', {});
  const dragstart = (event: DragEvent) => {
    const selection = window.getSelection();
    if (!event.dataTransfer || !selection || selection.isCollapsed || selection.rangeCount !== 1
        || !root.contains(selection.anchorNode) || !root.contains(selection.focusNode)) return;
    // Preserve ordinary link/image dragging outside the selected passage.
    if (![...selection.getRangeAt(0).getClientRects()].some(rect =>
      event.clientX >= rect.left && event.clientX <= rect.right
      && event.clientY >= rect.top && event.clientY <= rect.bottom)) return;
    const text = selection.toString();
    if (!text) return;
    event.dataTransfer.clearData();
    event.dataTransfer.setData('text/plain', text);
    event.dataTransfer.effectAllowed = 'copy';
    interact();
  };
  const selected = () => {
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed && root.contains(selection.anchorNode)) interact();
  };
  root.addEventListener('pointerdown', interact);
  root.addEventListener('keydown', interact);
  root.ownerDocument.addEventListener('selectionchange', selected);
  root.addEventListener('contextmenu', noteContextMenu);
  root.addEventListener('keydown', keydown);
  root.addEventListener('dragstart', dragstart);
  root.tabIndex = 0;
  const decorateObjects = () => {
    root.querySelectorAll<HTMLElement>('table, pre, .scholium-mermaid').forEach((element) => {
      if (element.closest('.scholium-mermaid') !== element && element.closest('.scholium-mermaid')) return;
      if (element.parentElement?.closest('pre, table, .scholium-mermaid')) return;
      element.dataset.replyObject = 'true';
    });
    root.querySelectorAll<HTMLElement>('[data-reply-object]').forEach((element) => {
      if (element.closest('.scholium-reply-object')) return;
      const wrapper = document.createElement('div'); wrapper.className = 'scholium-reply-object';
      const controls = document.createElement('div'); controls.className = 'scholium-reply-controls';
      controls.style.userSelect = 'none';
      for (const [label, symbol, action] of [['Copy', 'doc-on-doc', 'copy'], ['Expand', 'arrow-up-left-and-arrow-down-right', 'open']]) {
        const button = document.createElement('button');
        button.type = 'button';
        const icon = document.createElement('span'); icon.setAttribute('aria-hidden', 'true');
        icon.style.setProperty('--reply-symbol', `var(--scholium-system-symbol-${symbol})`); button.append(icon);
        button.title = localized(label); button.setAttribute('aria-label', localized(label));
        button.addEventListener('click', () => {
          const svg = element.querySelector('.scholium-mermaid-output')?.shadowRoot?.querySelector('svg');
          const box = svg?.viewBox.baseVal;
          const anchor = button.getBoundingClientRect();
          const index = [...root.querySelectorAll('[data-reply-object]')].indexOf(element);
          post('replyObject', {index, action, left: anchor.left, top: anchor.top, width: box?.width || element.scrollWidth,
            height: box?.height || element.getBoundingClientRect().height});
        }); controls.append(button);
      }
      // The renderer already supplies one table viewport; do not nest another
      // horizontal scroll owner inside it (or put the controls inside that viewport).
      const tableScroller = element.parentElement?.classList.contains('scholium-table-scroll') ? element.parentElement : null;
      if (tableScroller) {
        tableScroller.before(wrapper); wrapper.append(controls, tableScroller);
      } else {
        const scroller = document.createElement('div'); scroller.className = 'scholium-reply-object-scroll';
        element.before(wrapper); wrapper.append(controls, scroller); scroller.append(element);
      }
    });
  };
  decorateObjects();
  const reportSize = () => {
    // Measure a single paragraph with the same browser fonts and inline markup
    // that are painted. Restore layout before reporting its wrapped height;
    // no cloned content, alternate parser, or selection replacement is needed.
    let intrinsicWidth: number | null = null;
    const paragraph = root.firstElementChild;
    if (root.children.length === 1 && paragraph instanceof HTMLElement
        && paragraph.tagName === 'P' && !paragraph.querySelector('img, svg, .katex, br')) {
      const width = paragraph.style.width;
      const maximum = paragraph.style.maxWidth;
      paragraph.style.width = 'max-content';
      paragraph.style.maxWidth = 'none';
      intrinsicWidth = Math.ceil(paragraph.getBoundingClientRect().width);
      paragraph.style.width = width;
      paragraph.style.maxWidth = maximum;
    }
    post('replyLayout', {height: Math.ceil(root.getBoundingClientRect().height), intrinsicWidth});
  };
  const observer = new ResizeObserver(reportSize); observer.observe(root); reportSize();
  const dispose = () => {
    observer.disconnect();
    root.removeEventListener('keydown', keydown); root.removeEventListener('contextmenu', noteContextMenu);
    root.removeEventListener('dragstart', dragstart);
    root.removeEventListener('pointerdown', interact); root.removeEventListener('keydown', interact);
    root.ownerDocument.removeEventListener('selectionchange', selected);
  };
  return Object.assign(dispose, {refresh: () => { decorateObjects(); reportSize(); }});
}

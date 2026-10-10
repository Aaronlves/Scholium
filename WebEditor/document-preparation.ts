export interface DocumentPreparationHandle {
  /** Repaints from the document's current measured viewport; never lays it out. */
  refresh(): void;
  finish(): void;
}

const activePreparations = new WeakMap<Document, DocumentPreparationHandle>();
const visualObjects = 'img, svg, canvas, video, input, textarea, .scholium-mermaid';
const transientEditorPaint = '.cm-cursorLayer, .cm-selectionLayer, .cm-tooltip';
const maximumPaintRects = 384;
const maximumTextNodes = 768;
const maximumVisitedNodes = 4096;

/**
 * A paint-only mask of this same document's real visible text runs and objects.
 * The caller owns document identity, rendering readiness and initial scroll.
 * No placeholder text, CodeMirror DOM changes or independent layout is created.
 */
export function beginDocumentPreparation(root: HTMLElement): DocumentPreparationHandle {
  const document = root.ownerDocument;
  activePreparations.get(document)?.finish();
  const owner = document.defaultView;
  const previousAccessibility = root.getAttribute('aria-hidden');
  root.setAttribute('aria-hidden', 'true');

  const mask = document.createElement('div');
  mask.className = 'scholium-document-preparation';
  mask.setAttribute('aria-hidden', 'true');
  const paint = document.createElement('div');
  paint.className = 'scholium-document-preparation-paint';
  mask.appendChild(paint);
  document.body.appendChild(mask);
  const reducedMotion = owner?.matchMedia('(prefers-reduced-motion: reduce)');
  const updateMotion = () => mask.classList.toggle('scholium-document-preparation-static', reducedMotion?.matches ?? true);
  let finished = false;

  function refresh() {
    if (finished || !owner) return;
    if (!root.isConnected) { finish(); return; }
    const width = owner.innerWidth, height = owner.innerHeight;
    const fragment = document.createDocumentFragment();
    const painted = new Set<string>();
    let examinedTextNodes = 0;
    const appendRect = (rect: DOMRect) => {
      if (painted.size >= maximumPaintRects) return;
      const left = Math.max(0, rect.left), top = Math.max(0, rect.top);
      const right = Math.min(width, rect.right), bottom = Math.min(height, rect.bottom);
      if (![left, top, right, bottom].every(Number.isFinite) || right <= left || bottom <= top) return;
      const key = [left, top, right, bottom].join(':');
      if (painted.has(key)) return;
      painted.add(key);
      const shape = document.createElement('div');
      shape.className = 'scholium-document-preparation-shape';
      Object.assign(shape.style, {
        left: `${left}px`, top: `${top}px`,
        width: `${right - left}px`, height: `${bottom - top}px`,
      });
      fragment.appendChild(shape);
    };
    // Read the real DOM geometry without hit-testing or toggling input state.
    // Native surface visibility owns input; this mask only paints. Prune
    // offscreen branches and bound work/paint.
    let node: Node | null = root.firstChild;
    let visited = 0;
    while (node && visited++ < maximumVisitedNodes && painted.size < maximumPaintRects) {
      let skipChildren = false;
      if (node.nodeType === 1) {
        const element = node as Element;
        const bounds = element.getBoundingClientRect();
        skipChildren = element.matches(transientEditorPaint)
          || (bounds.width > 0 && bounds.height > 0
            && (bounds.right <= 0 || bounds.bottom <= 0 || bounds.left >= width || bounds.top >= height));
        if (!skipChildren && element.matches(visualObjects)) {
          appendRect(bounds);
          skipChildren = true;
        }
      } else if (node.nodeType === 3 && node.textContent?.trim() && examinedTextNodes++ < maximumTextNodes) {
        const range = document.createRange();
        range.selectNodeContents(node);
        for (const rect of range.getClientRects()) {
          appendRect(rect);
          if (painted.size >= maximumPaintRects) break;
        }
      }
      if (!skipChildren && node.firstChild) { node = node.firstChild; continue; }
      while (node && node !== root && !node.nextSibling) node = node.parentNode;
      node = node === root ? null : node?.nextSibling ?? null;
    }
    paint.replaceChildren(fragment);
  }

  function finish() {
    if (finished) return;
    finished = true;
    mask.remove();
    if (previousAccessibility === null) root.removeAttribute('aria-hidden');
    else root.setAttribute('aria-hidden', previousAccessibility);
    owner?.removeEventListener('resize', refresh);
    owner?.removeEventListener('scroll', refresh, true);
    owner?.removeEventListener('pagehide', finish);
    reducedMotion?.removeEventListener('change', updateMotion);
    if (activePreparations.get(document) === handle) activePreparations.delete(document);
  }

  const handle = {refresh, finish};
  activePreparations.set(document, handle);
  owner?.addEventListener('resize', refresh);
  owner?.addEventListener('scroll', refresh, {capture: true, passive: true});
  owner?.addEventListener('pagehide', finish, {once: true});
  reducedMotion?.addEventListener('change', updateMotion);
  updateMotion();
  refresh();
  return handle;
}

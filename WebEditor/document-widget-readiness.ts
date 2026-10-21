export interface DocumentWidgetPreparation {
  /** Rendering or the existing source fallback has reached its final DOM. */
  finish(): void;
}

interface PendingWidget extends DocumentWidgetPreparation {
  readonly node: HTMLElement;
  readonly ready: Promise<void>;
}

const pendingWidgets = new WeakMap<Document, Map<HTMLElement, PendingWidget>>();

function widgetIsVisible(entry: PendingWidget, root: HTMLElement, viewport: HTMLElement) {
  if (!root.isConnected || !entry.node.isConnected || !root.contains(entry.node)) return false;
  const bounds = viewport.getBoundingClientRect();
  const rect = entry.node.getBoundingClientRect();
  return rect.right >= bounds.left && rect.left <= bounds.right
    && rect.bottom >= bounds.top && rect.top <= bounds.bottom;
}

/** Counts the actual readiness registry, including mathematics source fallbacks. */
export function pendingVisibleDocumentWidgetCounts(root: HTMLElement, viewport: HTMLElement) {
  const counts = {math: 0, mermaid: 0, other: 0};
  for (const entry of pendingWidgets.get(root.ownerDocument)?.values() ?? []) {
    if (!widgetIsVisible(entry, root, viewport)) continue;
    if (entry.node.matches(".scholium-math")) counts.math++;
    else if (entry.node.matches(".cm-live-mermaid-widget")) counts.mermaid++;
    else counts.other++;
  }
  return counts;
}

/** Tracks work owned by a real widget, without changing its DOM or geometry. */
export function beginDocumentWidgetPreparation(node: HTMLElement): DocumentWidgetPreparation {
  const document = node.ownerDocument;
  let pending = pendingWidgets.get(document);
  if (!pending) pendingWidgets.set(document, pending = new Map());
  const widgets = pending;
  widgets.get(node)?.finish();
  let resolve!: () => void;
  const ready = new Promise<void>(complete => { resolve = complete; });
  const entry: PendingWidget = {
    node,
    ready,
    finish() {
      if (widgets.get(node) === entry) widgets.delete(node);
      resolve();
    },
  };
  widgets.set(node, entry);
  return entry;
}

/**
 * Waits only for pending widgets in this document's actual current viewport.
 * The caller owns identity/deadline admission, scrolling and the subsequent
 * editor measurement. It calls again after that measurement, because completed
 * widgets or restored scrolling can bring a different widget into the viewport.
 */
export async function awaitVisibleDocumentWidgets(
  root: HTMLElement,
  viewport: HTMLElement,
  requireCurrent: () => void,
): Promise<boolean> {
  requireCurrent();
  const visible = (entry: PendingWidget) => widgetIsVisible(entry, root, viewport);
  const pending = new Set(Array.from(pendingWidgets.get(root.ownerDocument)?.values() ?? [])
    .filter(visible));
  if (pending.size === 0) return false;
  const owner = root.ownerDocument.defaultView!;
  await new Promise<void>((resolve, reject) => {
    let finished = false;
    const finish = (error?: unknown) => {
      if (finished) return;
      finished = true;
      observer.disconnect();
      viewport.removeEventListener("scroll", check);
      owner.removeEventListener("resize", check);
      if (error === undefined) resolve();
      else reject(error);
    };
    const check = () => {
      try {
        requireCurrent();
        for (const entry of pending) if (!visible(entry)) pending.delete(entry);
        if (pending.size === 0) finish();
      } catch (error) { finish(error); }
    };
    const observer = new (owner as Window & typeof globalThis).MutationObserver(check);
    observer.observe(root.ownerDocument.documentElement, {childList: true, subtree: true});
    viewport.addEventListener("scroll", check, {passive: true});
    owner.addEventListener("resize", check);
    for (const entry of pending) {
      void entry.ready.then(() => {
        pending.delete(entry);
        check();
      });
    }
    check();
  });
  requireCurrent();
  return true;
}

/** Native notifies after refreshing installed math, or retaining source on failure. */
export const mathRuntimeSettledEvent = "scholium-math-runtime-settled";

interface DocumentImageResource {
  source: string | null;
  revision: number;
}
const imageResourceRevisions = new WeakMap<HTMLImageElement, number>();

export function createDocumentImageReadiness() {
  return new WeakMap<HTMLImageElement, DocumentImageResource>();
}

/** Catalog replacement retains the image node, including when a filename is
 * removed and restored before the next layout preparation observes it. */
export function invalidateDocumentImageReadiness(image: HTMLImageElement) {
  imageResourceRevisions.set(image, (imageResourceRevisions.get(image) ?? 0) + 1);
}

/** The same visible, source-backed media barrier serves Edit and Review. */
export async function awaitVisibleDocumentImages(
  root: HTMLElement,
  viewport: Pick<DOMRectReadOnly, "left" | "right" | "top" | "bottom">,
  decoded: ReturnType<typeof createDocumentImageReadiness>,
  requireCurrent: () => void,
  applyDecoded: (image: HTMLImageElement) => void,
): Promise<boolean> {
  requireCurrent();
  const pending = Array.from(root.querySelectorAll<HTMLImageElement>("img"))
    .map(image => ({image, source: image.getAttribute("src"), revision: imageResourceRevisions.get(image) ?? 0}))
    .filter(({image, source, revision}) => {
      const previous = decoded.get(image);
      if (!image.isConnected || previous?.source === source && previous.revision === revision) return false;
      const imageRect = image.getBoundingClientRect();
      // Undecoded images can have no size; their actual owner locates them
      // without introducing an invented placeholder or a second layout.
      const rect = imageRect.width > 0 && imageRect.height > 0
        ? imageRect : image.parentElement!.getBoundingClientRect();
      return rect.bottom >= viewport.top && rect.top <= viewport.bottom
        && rect.right >= viewport.left && rect.left <= viewport.right;
    });
  if (pending.length === 0) return false;
  for (const {image} of pending) decoded.delete(image);
  // Failure keeps the existing image/alt presentation and exact source.
  await Promise.all(pending.map(({image}) => image.decode().catch(() => {})));
  requireCurrent();
  for (const {image, source, revision} of pending) {
    // Catalog refresh retains this DOM node. A decode of its previous src
    // cannot settle the replacement resource or apply its old dimensions.
    if (!image.isConnected || !root.contains(image) || image.getAttribute("src") !== source
        || (imageResourceRevisions.get(image) ?? 0) !== revision) continue;
    decoded.set(image, {source, revision});
    applyDecoded(image);
  }
  return true;
}

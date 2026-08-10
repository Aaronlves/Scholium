import type {Extension} from "@codemirror/state";
import {EditorView, ViewPlugin} from "@codemirror/view";
import {announceEditorMessage} from "./accessibility";
import {floatingSurfacePosition} from "./floating-surface-geometry";
import {recordEditorMetric} from "./performance";
import type {LinkPreview} from "./previews";

type PreviewAnchorRect = Pick<DOMRect, "left" | "right" | "top" | "bottom">;

function normalizedTitle(value: string) {
  return value.trim().replace(/\s+/g, " ").toLocaleLowerCase();
}

/** Installs inert rendered content while retaining the shared Document CSS owner. */
export function populatePreviewDocument(body: HTMLElement, preview: LinkPreview) {
  body.innerHTML = preview.htmlBody;
  body.querySelectorAll("script, style, iframe, object, embed, form, input, button")
    .forEach((node) => node.remove());
  body.querySelectorAll<HTMLElement>("*").forEach((node) => {
    for (const attribute of Array.from(node.attributes)) {
      if (attribute.name.toLowerCase().startsWith("on")) node.removeAttribute(attribute.name);
      if (attribute.name.toLowerCase().startsWith("data-source-")) {
        node.removeAttribute(attribute.name);
      }
    }
    node.removeAttribute("href");
    node.removeAttribute("contenteditable");
    node.removeAttribute("id");
    node.removeAttribute("for");
    node.removeAttribute("aria-describedby");
    node.removeAttribute("aria-labelledby");
    node.removeAttribute("aria-owns");
    node.tabIndex = -1;
  });
  const firstHeading = body.querySelector<HTMLElement>(":scope > h1:first-child");
  if (firstHeading && normalizedTitle(firstHeading.textContent ?? "") === normalizedTitle(preview.title)) {
    firstHeading.remove();
  }
}

export interface PreviewPopoverController {
  readonly extension: Extension;
  hide(): void;
  showAtSelection(): boolean;
  showAtPoint(x: number, y: number): boolean;
}

/** Owns cached-link preview presentation without owning preview data or source. */
export function createPreviewPopoverController(
  options: {
    previews(): readonly LinkPreview[];
  },
): PreviewPopoverController {
  let editor: EditorView | null = null;
  let root: HTMLElement | null = null;
  let title: HTMLElement | null = null;
  let metadata: HTMLElement | null = null;
  let body: HTMLElement | null = null;
  let showTimer: number | undefined;
  let hideTimer: number | undefined;
  let pendingAnchor: HTMLElement | null = null;

  function hide() {
    window.clearTimeout(showTimer);
    window.clearTimeout(hideTimer);
    showTimer = undefined;
    hideTimer = undefined;
    pendingAnchor = null;
    if (root) {
      root.hidden = true;
      root.style.visibility = "";
    }
    if (title) title.textContent = "";
    if (metadata) metadata.textContent = "";
    body?.replaceChildren();
  }

  function cancelHide() {
    window.clearTimeout(hideTimer);
    hideTimer = undefined;
  }

  function scheduleHide() {
    window.clearTimeout(hideTimer);
    hideTimer = window.setTimeout(hide, 180);
  }

  function position(anchor: PreviewAnchorRect, startedAt: number) {
    if (!editor || !root) return;
    const activeEditor = editor;
    const activeRoot = root;
    activeRoot.style.visibility = "hidden";
    activeRoot.hidden = false;
    const inset = 12;
    const gap = 8;
    activeEditor.requestMeasure({
      read: () => ({
        measured: activeRoot.getBoundingClientRect(),
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
      }),
      write: ({measured, viewportWidth, viewportHeight}) => {
        if (activeRoot.hidden || editor !== activeEditor || root !== activeRoot) return;
        const resolved = floatingSurfacePosition({
          anchor,
          surface: measured,
          viewport: {width: viewportWidth, height: viewportHeight},
          horizontal: "start",
          preferredPlacement: "below",
          inset,
          gap,
        });
        activeRoot.style.left = `${resolved.left}px`;
        activeRoot.style.top = `${resolved.top}px`;
        activeRoot.style.visibility = "visible";
        window.requestAnimationFrame(() => recordEditorMetric("cached-preview", startedAt, {
          documentLength: activeEditor.state.doc.length,
        }));
      },
    });
  }

  function show(preview: LinkPreview, anchor: PreviewAnchorRect, startedAt: number) {
    if (!editor || !root || !title || !metadata || !body) return;
    title.textContent = preview.title;
    metadata.textContent = preview.fragment ?? "";
    metadata.hidden = !preview.fragment;
    populatePreviewDocument(body, preview);
    recordEditorMetric("cached-preview-work", startedAt, {
      documentLength: editor.state.doc.length,
    });
    position(anchor, startedAt);
  }

  function showAtSelection() {
    const startedAt = performance.now();
    if (!editor) return false;
    const head = editor.state.selection.main.head;
    const coords = editor.coordsAtPos(head);
    if (!coords) return false;
    const preview = options.previews().find((candidate) => head >= candidate.from && head < candidate.to);
    if (preview) {
      show(preview, coords, startedAt);
      return true;
    }
    announceEditorMessage(editor.contentDOM, "No preview is available at the insertion point.");
    return false;
  }

  function showAtPoint(x: number, y: number) {
    const startedAt = performance.now();
    if (!editor) return false;
    const anchor = document.elementFromPoint(x, y)?.closest<HTMLElement>("[data-link-preview-index]");
    if (!anchor) return showAtSelection();
    const previewIndex = Number(anchor.dataset.linkPreviewIndex);
    const preview = options.previews()[previewIndex];
    if (Number.isInteger(previewIndex) && preview) {
      show(preview, anchor.getBoundingClientRect(), startedAt);
      return true;
    }
    return showAtSelection();
  }

  function anchorAtEvent(event: PointerEvent) {
    if (!event.metaKey || !(event.target instanceof Element)) {
      return null;
    }
    return event.target.closest<HTMLElement>("[data-link-preview-index]");
  }

  const handlePointerMove = (event: PointerEvent) => {
    if (root && event.target instanceof Node && root.contains(event.target)) {
      cancelHide();
      return;
    }
    const anchor = anchorAtEvent(event);
    if (!anchor) {
      if (pendingAnchor || (root && !root.hidden)) scheduleHide();
      return;
    }
    cancelHide();
    if (anchor === pendingAnchor) return;
    window.clearTimeout(showTimer);
    showTimer = undefined;
    pendingAnchor = anchor;
    showTimer = window.setTimeout(() => {
      if (pendingAnchor !== anchor) return;
      const previewIndex = Number(anchor.dataset.linkPreviewIndex);
      const preview = options.previews()[previewIndex];
      if (Number.isInteger(previewIndex) && preview) {
        show(preview, anchor.getBoundingClientRect(), performance.now());
      }
    }, 300);
  };
  const handlePreviewPointerEnter = () => cancelHide();
  const handlePreviewPointerLeave = () => scheduleHide();
  const handleKeyUp = (event: KeyboardEvent) => {
    if (event.key === "Meta") hide();
  };
  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.key === "Escape" && root && !root.hidden) hide();
  };
  const handleViewportExit = () => hide();

  function mount(view: EditorView) {
    if (editor) return;
    editor = view;
    root = document.createElement("aside");
    root.id = "scholium-preview-popover";
    root.className = "scholium-preview-popover";
    root.dataset.scholiumProtected = "preview-popover";
    root.setAttribute("role", "tooltip");
    root.setAttribute("aria-live", "polite");
    root.hidden = true;

    title = document.createElement("h2");
    title.className = "scholium-preview-title";
    metadata = document.createElement("p");
    metadata.className = "scholium-preview-metadata";
    metadata.hidden = true;
    body = document.createElement("div");
    body.className = "scholium-preview-body scholium-document";
    body.setAttribute("role", "group");
    body.setAttribute("aria-label", "Preview content");
    root.append(title, metadata, body);
    document.body.append(root);
    root.addEventListener("pointerenter", handlePreviewPointerEnter);
    root.addEventListener("pointerleave", handlePreviewPointerLeave);
    document.addEventListener("pointermove", handlePointerMove, {passive: true});
    document.addEventListener("keyup", handleKeyUp);
    document.addEventListener("keydown", handleKeyDown);
    view.scrollDOM.addEventListener("scroll", handleViewportExit, {passive: true});
    window.addEventListener("resize", handleViewportExit);
    window.addEventListener("blur", handleViewportExit);
  }

  function unmount(view: EditorView) {
    if (editor !== view) return;
    hide();
    document.removeEventListener("pointermove", handlePointerMove);
    document.removeEventListener("keyup", handleKeyUp);
    document.removeEventListener("keydown", handleKeyDown);
    view.scrollDOM.removeEventListener("scroll", handleViewportExit);
    root?.removeEventListener("pointerenter", handlePreviewPointerEnter);
    root?.removeEventListener("pointerleave", handlePreviewPointerLeave);
    window.removeEventListener("resize", handleViewportExit);
    window.removeEventListener("blur", handleViewportExit);
    root?.remove();
    root = null;
    title = null;
    metadata = null;
    body = null;
    editor = null;
  }

  const extension = ViewPlugin.define((view) => {
    mount(view);
    return {destroy: () => unmount(view)};
  });

  return {extension, hide, showAtSelection, showAtPoint};
}

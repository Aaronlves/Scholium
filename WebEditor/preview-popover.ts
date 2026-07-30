import type {EditorView} from "@codemirror/view";
import {announceEditorMessage} from "./accessibility";
import {recordEditorMetric} from "./performance";
import type {LinkPreview, VectorLinkKind} from "./previews";

type PreviewAnchorRect = Pick<DOMRect, "left" | "right" | "top" | "bottom">;

const relationshipLabels: Record<VectorLinkKind, string> = {
  neutral: "Related note",
  supports: "Supports",
  opposes: "Opposes",
  incompatible: "Incompatible",
};

export interface PreviewPopoverController {
  hide(): void;
  showAtSelection(): boolean;
  showAtPoint(x: number, y: number): boolean;
}

/** Owns cached-link preview presentation without owning preview data or source. */
export function createPreviewPopoverController(
  editor: EditorView,
  options: {
    mode(): "livePreview" | "source";
    previews(): readonly LinkPreview[];
  },
): PreviewPopoverController {
  const root = document.createElement("aside");
  root.id = "scholium-preview-popover";
  root.className = "scholium-preview-popover";
  root.dataset.scholiumProtected = "preview-popover";
  root.setAttribute("role", "tooltip");
  root.setAttribute("aria-live", "polite");
  root.hidden = true;

  const title = document.createElement("h2");
  title.className = "scholium-preview-title";
  const metadata = document.createElement("p");
  metadata.className = "scholium-preview-metadata";
  const body = document.createElement("div");
  body.className = "scholium-preview-body";
  body.setAttribute("role", "group");
  body.setAttribute("aria-label", "Preview content");
  root.append(title, metadata, body);
  document.body.append(root);

  let timer: number | undefined;
  let pendingAnchor: HTMLElement | null = null;

  function hide() {
    window.clearTimeout(timer);
    timer = undefined;
    pendingAnchor = null;
    root.hidden = true;
    root.style.visibility = "";
    title.textContent = "";
    metadata.textContent = "";
    body.replaceChildren();
  }

  function position(anchor: PreviewAnchorRect, startedAt: number) {
    root.style.visibility = "hidden";
    root.hidden = false;
    const inset = 12;
    const gap = 8;
    editor.requestMeasure({
      read: () => ({
        measured: root.getBoundingClientRect(),
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
      }),
      write: ({measured, viewportWidth, viewportHeight}) => {
        if (root.hidden) return;
        const left = Math.max(inset, Math.min(anchor.left, viewportWidth - measured.width - inset));
        const below = anchor.bottom + gap;
        const top = below + measured.height <= viewportHeight - inset
          ? below
          : Math.max(inset, anchor.top - measured.height - gap);
        root.style.left = `${left}px`;
        root.style.top = `${top}px`;
        root.style.visibility = "visible";
        window.requestAnimationFrame(() => recordEditorMetric("cached-preview", startedAt, {
          documentLength: editor.state.doc.length,
        }));
      },
    });
  }

  function removeInteractiveContent() {
    body.querySelectorAll("script, style, iframe, object, embed, form, input, button")
      .forEach((node) => node.remove());
    body.querySelectorAll<HTMLElement>("*").forEach((node) => {
      for (const attribute of Array.from(node.attributes)) {
        if (attribute.name.toLowerCase().startsWith("on")) node.removeAttribute(attribute.name);
      }
      node.removeAttribute("href");
      node.removeAttribute("contenteditable");
      node.tabIndex = -1;
    });
  }

  function show(preview: LinkPreview, anchor: PreviewAnchorRect, startedAt: number) {
    title.textContent = preview.title;
    const relationship = preview.relationship ? relationshipLabels[preview.relationship] : "Related note";
    metadata.textContent = preview.fragment ? `${relationship}\n${preview.fragment}` : relationship;
    body.innerHTML = preview.htmlBody;
    removeInteractiveContent();
    recordEditorMetric("cached-preview-work", startedAt, {
      documentLength: editor.state.doc.length,
    });
    position(anchor, startedAt);
  }

  function showAtSelection() {
    const startedAt = performance.now();
    if (options.mode() !== "livePreview") return false;
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
    if (options.mode() !== "livePreview") return false;
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
    if (!event.metaKey || options.mode() !== "livePreview" || !(event.target instanceof Element)) {
      return null;
    }
    return event.target.closest<HTMLElement>("[data-link-preview-index]");
  }

  document.addEventListener("pointermove", (event) => {
    const anchor = anchorAtEvent(event);
    if (!anchor) {
      if (pendingAnchor || !root.hidden) hide();
      return;
    }
    if (anchor === pendingAnchor) return;
    hide();
    pendingAnchor = anchor;
    timer = window.setTimeout(() => {
      if (pendingAnchor !== anchor) return;
      const previewIndex = Number(anchor.dataset.linkPreviewIndex);
      const preview = options.previews()[previewIndex];
      if (Number.isInteger(previewIndex) && preview) {
        show(preview, anchor.getBoundingClientRect(), performance.now());
      }
    }, 300);
  }, {passive: true});
  document.addEventListener("keyup", (event) => {
    if (event.key === "Meta") hide();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !root.hidden) hide();
  });

  return {hide, showAtSelection, showAtPoint};
}

import type {Extension} from "@codemirror/state";
import {EditorView, ViewPlugin} from "@codemirror/view";
import {announceEditorMessage} from "./accessibility";
import {floatingSurfacePosition} from "./floating-surface-geometry";
import type {
  FootnotePresentation,
  FootnoteReferencePresentation,
} from "./footnote-presentation";
import {
  recordEditorMetric,
  scheduleAfterNextPaint,
} from "./performance";
import type {LinkPreview} from "./previews";
import {localized, localizedTemplate} from "./localization";

type PreviewAnchorRect = Pick<DOMRect, "left" | "right" | "top" | "bottom">;

function normalizedTitle(value: string) {
  return value.trim().replace(/\s+/g, " ").toLocaleLowerCase();
}

function sanitizePreviewDocument(body: HTMLElement) {
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
}

/** Installs inert rendered content while retaining the shared Document CSS owner. */
export function populatePreviewDocument(body: HTMLElement, preview: LinkPreview) {
  body.innerHTML = preview.htmlBody;
  sanitizePreviewDocument(body);
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

/** Owns cached-link, footnote, and source-owned annotation previews without owning source. */
export function createPreviewPopoverController(
  options: {
    previews(): readonly LinkPreview[];
    footnotes(): FootnotePresentation;
    renderFootnoteContent(content: string, parent: HTMLElement): void;
    postPerformanceSample(
      metric: "editor_cached_preview",
      durationMilliseconds: number,
    ): void;
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
  let hoveredLink: HTMLElement | null = null;
  let armedLink: HTMLElement | null = null;
  let activeAnnotationButton: HTMLButtonElement | null = null;
  let pinnedAnnotationButton: HTMLButtonElement | null = null;
  let activeFootnoteButton: HTMLButtonElement | null = null;
  let pinnedFootnoteButton: HTMLButtonElement | null = null;
  let activeKind: "link" | "annotation" | "footnote" | null = null;
  let modifierPressed = false;

  function annotationTarget(button: HTMLButtonElement) {
    return button.dataset.linkAnnotationTarget?.trim() || localized("linked note");
  }

  function setAnnotationExpanded(button: HTMLButtonElement, expanded: boolean) {
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    button.setAttribute(
      "aria-label",
      `${localized(expanded ? "Hide Link Annotation" : "Show Link Annotation")} ${annotationTarget(button)}`,
    );
  }

  function setFootnoteExpanded(button: HTMLButtonElement, expanded: boolean) {
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
  }

  function hasPinnedPreview() {
    return pinnedAnnotationButton !== null || pinnedFootnoteButton !== null;
  }

  function setArmedLink(next: HTMLElement | null) {
    if (armedLink === next) return;
    armedLink?.classList.remove("scholium-link-preview-armed");
    armedLink = next;
    armedLink?.classList.add("scholium-link-preview-armed");
  }

  function hide(retainHoveredLink = false) {
    window.clearTimeout(showTimer);
    window.clearTimeout(hideTimer);
    showTimer = undefined;
    hideTimer = undefined;
    pendingAnchor = null;
    if (!retainHoveredLink) hoveredLink = null;
    modifierPressed = false;
    setArmedLink(null);
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = null;
    pinnedAnnotationButton = null;
    activeFootnoteButton = null;
    pinnedFootnoteButton = null;
    activeKind = null;
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
    if (hasPinnedPreview()) return;
    window.clearTimeout(hideTimer);
    hideTimer = window.setTimeout(hide, 180);
  }

  function position(anchor: PreviewAnchorRect, startedAt?: number) {
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
        if (startedAt === undefined) return;
        scheduleAfterNextPaint(() => {
          const durationMilliseconds = Math.max(0, performance.now() - startedAt);
          recordEditorMetric("cached-preview", startedAt, {
            documentLength: activeEditor.state.doc.length,
          });
          options.postPerformanceSample(
            "editor_cached_preview",
            durationMilliseconds,
          );
        });
      },
    });
  }

  function showLinkPreview(preview: LinkPreview, anchor: PreviewAnchorRect, startedAt: number) {
    if (!editor || !root || !title || !metadata || !body) return;
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = null;
    activeFootnoteButton = null;
    activeKind = "link";
    title.textContent = preview.title;
    metadata.textContent = preview.fragment ?? "";
    metadata.hidden = !preview.fragment;
    populatePreviewDocument(body, preview);
    recordEditorMetric("cached-preview-work", startedAt, {
      documentLength: editor.state.doc.length,
    });
    position(anchor, startedAt);
  }

  function annotationTemplate(button: HTMLButtonElement) {
    const owner = button.closest<HTMLElement>(
      ".scholium-link-annotation-disclosure, .scholium-link-annotation-marker",
    );
    return owner?.querySelector<HTMLTemplateElement>(":scope > template") ?? null;
  }

  function showAnnotation(button: HTMLButtonElement) {
    if (!root || !title || !metadata || !body) return false;
    const template = annotationTemplate(button);
    if (!template) return false;
    if (activeAnnotationButton && activeAnnotationButton !== button) {
      setAnnotationExpanded(activeAnnotationButton, false);
    }
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = button;
    activeFootnoteButton = null;
    activeKind = "annotation";
    setAnnotationExpanded(button, true);
    title.textContent = annotationTarget(button);
    metadata.textContent = localized("Link Annotation");
    metadata.hidden = false;
    body.replaceChildren(template.content.cloneNode(true));
    sanitizePreviewDocument(body);
    position(button.getBoundingClientRect());
    return true;
  }

  function footnoteReferenceFor(button: HTMLButtonElement) {
    const identifier = button.dataset.footnoteIdentifier;
    const occurrence = Number(button.dataset.footnoteOccurrence);
    if (!identifier || !Number.isInteger(occurrence)) return undefined;
    return options.footnotes().references.find((reference) =>
      reference.identifier === identifier && reference.occurrence === occurrence);
  }

  function showFootnoteReference(
    reference: FootnoteReferencePresentation,
    anchor: PreviewAnchorRect,
    button: HTMLButtonElement | null = null,
  ) {
    if (!root || !title || !metadata || !body) return false;
    const definition = options.footnotes().definitions.find((candidate) =>
      candidate.identifier === reference.identifier);
    const content = definition?.content.trim().slice(0, 1_600) ?? "";
    if (!content) return false;
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton && activeFootnoteButton !== button) {
      setFootnoteExpanded(activeFootnoteButton, false);
    }
    activeAnnotationButton = null;
    activeFootnoteButton = button;
    activeKind = "footnote";
    if (button) setFootnoteExpanded(button, true);
    title.textContent = localizedTemplate("Footnote {ordinal}", {ordinal: reference.ordinal});
    metadata.textContent = "";
    metadata.hidden = true;
    body.replaceChildren();
    options.renderFootnoteContent(content, body);
    sanitizePreviewDocument(body);
    position(anchor);
    return true;
  }

  function showFootnote(button: HTMLButtonElement) {
    const reference = footnoteReferenceFor(button);
    return reference
      ? showFootnoteReference(reference, button.getBoundingClientRect(), button)
      : false;
  }

  function showAtSelection() {
    const startedAt = performance.now();
    if (!editor) return false;
    const head = editor.state.selection.main.head;
    const coords = editor.coordsAtPos(head);
    if (!coords) return false;
    const footnote = options.footnotes().references.find((candidate) =>
      head >= candidate.from && head < candidate.to);
    if (footnote) {
      hide();
      return showFootnoteReference(footnote, coords);
    }
    const preview = options.previews().find((candidate) => head >= candidate.from && head < candidate.to);
    if (preview) {
      hide();
      showLinkPreview(preview, coords, startedAt);
      return true;
    }
    announceEditorMessage(
      editor.contentDOM,
      localized("No preview is available at the insertion point."),
    );
    return false;
  }

  function showAtPoint(x: number, y: number) {
    const startedAt = performance.now();
    if (!editor) return false;
    const anchor = linkAnchorAt(document.elementFromPoint(x, y));
    const footnote = footnoteButtonAt(document.elementFromPoint(x, y));
    if (footnote) {
      hide();
      return showFootnote(footnote);
    }
    if (!anchor) return showAtSelection();
    const preview = previewForAnchor(anchor);
    if (preview) {
      hide();
      showLinkPreview(preview, anchor.getBoundingClientRect(), startedAt);
      return true;
    }
    return showAtSelection();
  }

  function annotationButtonAt(target: EventTarget | null) {
    return target instanceof Element
      ? target.closest<HTMLButtonElement>(".scholium-link-annotation-button")
      : null;
  }

  function footnoteButtonAt(target: EventTarget | null) {
    return target instanceof Element
      ? target.closest<HTMLButtonElement>(".cm-live-footnote-reference-widget .footnote-reference")
      : null;
  }

  function linkAnchorAt(target: EventTarget | null) {
    return target instanceof Element
      ? target.closest<HTMLElement>(
        "[data-link-preview-index], [data-scholium-link-target][data-scholium-source-from][data-scholium-source-to]",
      )
      : null;
  }

  function previewForAnchor(anchor: HTMLElement) {
    const previewIndex = Number(anchor.dataset.linkPreviewIndex);
    if (Number.isInteger(previewIndex) && anchor.dataset.linkPreviewIndex !== undefined) {
      return options.previews()[previewIndex];
    }
    const from = Number(anchor.dataset.scholiumSourceFrom);
    const to = Number(anchor.dataset.scholiumSourceTo);
    if (!Number.isSafeInteger(from) || !Number.isSafeInteger(to) || to <= from) return undefined;
    return options.previews().find((preview) => preview.from === from && preview.to === to);
  }

  function scheduleShow(anchor: HTMLElement, kind: "link" | "annotation" | "footnote") {
    cancelHide();
    if (anchor === pendingAnchor && kind === activeKind) return;
    window.clearTimeout(showTimer);
    showTimer = undefined;
    pendingAnchor = anchor;
    showTimer = window.setTimeout(() => {
      if (pendingAnchor !== anchor) return;
      if (kind === "annotation") {
        showAnnotation(anchor as HTMLButtonElement);
        return;
      }
      if (kind === "footnote") {
        showFootnote(anchor as HTMLButtonElement);
        return;
      }
      const preview = previewForAnchor(anchor);
      if (preview) {
        showLinkPreview(preview, anchor.getBoundingClientRect(), performance.now());
      }
    }, 300);
  }

  const handlePointerMove = (event: PointerEvent) => {
    if (root && event.target instanceof Node && root.contains(event.target)) {
      cancelHide();
      return;
    }
    const annotation = annotationButtonAt(event.target);
    const footnote = footnoteButtonAt(event.target);
    const link = linkAnchorAt(event.target);
    hoveredLink = link;
    if (hasPinnedPreview()
        && annotation !== pinnedAnnotationButton
        && footnote !== pinnedFootnoteButton) {
      setArmedLink(null);
      return;
    }
    const modifierActive = event.metaKey || event.ctrlKey || modifierPressed;
    setArmedLink(modifierActive ? link : null);
    const anchor = annotation ?? footnote ?? (modifierActive ? link : null);
    if (!anchor) {
      if (pendingAnchor || (root && !root.hidden)) scheduleHide();
      return;
    }
    scheduleShow(anchor, annotation ? "annotation" : footnote ? "footnote" : "link");
  };
  const handlePreviewPointerEnter = () => cancelHide();
  const handlePreviewPointerLeave = () => scheduleHide();
  const handleKeyUp = (event: KeyboardEvent) => {
    if (event.key !== "Meta" && event.key !== "Control") return;
    modifierPressed = false;
    setArmedLink(null);
    if (activeKind === "link") hide(true);
  };
  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.key === "Escape" && root && !root.hidden) {
      hide();
      return;
    }
    if (event.key !== "Meta" && event.key !== "Control") return;
    modifierPressed = true;
    if (!hoveredLink || hasPinnedPreview()) return;
    setArmedLink(hoveredLink);
    scheduleShow(hoveredLink, "link");
  };
  const handleFocusIn = (event: FocusEvent) => {
    const button = annotationButtonAt(event.target) ?? footnoteButtonAt(event.target);
    if (!button) return;
    cancelHide();
    window.clearTimeout(showTimer);
    pendingAnchor = button;
    if (button.matches(".footnote-reference")) showFootnote(button);
    else showAnnotation(button);
  };
  const handleFocusOut = (event: FocusEvent) => {
    const button = annotationButtonAt(event.target) ?? footnoteButtonAt(event.target);
    if (!button) return;
    if (event.relatedTarget instanceof Node && root?.contains(event.relatedTarget)) return;
    scheduleHide();
  };
  const handleClick = (event: MouseEvent) => {
    const button = annotationButtonAt(event.target);
    if (button) {
      event.preventDefault();
      event.stopPropagation();
      if (pinnedAnnotationButton === button) {
        hide();
        return;
      }
      pinnedAnnotationButton = button;
      window.clearTimeout(showTimer);
      pendingAnchor = button;
      showAnnotation(button);
      return;
    }
    const footnote = footnoteButtonAt(event.target);
    if (footnote && event.detail === 0) {
      event.preventDefault();
      event.stopPropagation();
      if (pinnedFootnoteButton === footnote) {
        hide();
        return;
      }
      pinnedFootnoteButton = footnote;
      window.clearTimeout(showTimer);
      pendingAnchor = footnote;
      showFootnote(footnote);
      return;
    }
    if (hasPinnedPreview()
        && !(event.target instanceof Node && root?.contains(event.target))) hide();
  };
  const handleViewportExit = () => {
    hoveredLink = null;
    modifierPressed = false;
    hide();
  };

  function mount(view: EditorView) {
    if (editor) return;
    editor = view;
    root = document.createElement("aside");
    root.id = "scholium-preview-popover";
    root.className = "scholium-preview-popover";
    root.dataset.scholiumProtected = "preview-popover";
    root.setAttribute("role", "note");
    root.setAttribute("aria-labelledby", "scholium-preview-title");
    root.setAttribute("aria-live", "polite");
    root.hidden = true;

    title = document.createElement("h2");
    title.id = "scholium-preview-title";
    title.className = "scholium-preview-title";
    metadata = document.createElement("p");
    metadata.className = "scholium-preview-metadata";
    metadata.hidden = true;
    body = document.createElement("div");
    body.className = "scholium-preview-body scholium-document";
    body.setAttribute("role", "group");
    body.setAttribute("aria-label", localized("Preview content"));
    root.append(title, metadata, body);
    document.body.append(root);
    root.addEventListener("pointerenter", handlePreviewPointerEnter);
    root.addEventListener("pointerleave", handlePreviewPointerLeave);
    document.addEventListener("pointermove", handlePointerMove, {passive: true});
    document.addEventListener('focusin', handleFocusIn);
    document.addEventListener('focusout', handleFocusOut);
    document.addEventListener("click", handleClick);
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
    document.removeEventListener('focusin', handleFocusIn);
    document.removeEventListener('focusout', handleFocusOut);
    document.removeEventListener("click", handleClick);
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
    hoveredLink = null;
    modifierPressed = false;
  }

  const extension = ViewPlugin.define((view) => {
    mount(view);
    return {
      update(update) {
        if (update.docChanged || update.selectionSet || update.viewportChanged) hide();
      },
      destroy: () => unmount(view),
    };
  });

  return {extension, hide, showAtSelection, showAtPoint};
}

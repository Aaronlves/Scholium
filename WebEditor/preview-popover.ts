import type {Extension} from "@codemirror/state";
import {EditorView, ViewPlugin} from "@codemirror/view";
import {announceEditorMessage} from "./accessibility";
import {previewSurface, type NativePreviewPort} from "./native-floating";
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
import {sanitizePreviewDocument, renderPreviewMathNodes} from "./preview-document";
export {renderPreviewMathNodes} from "./preview-document";
import {localizeRenderedInterface} from "./rendered-interface-localization";

type PreviewAnchorRect = Pick<DOMRect, "left" | "right" | "top" | "bottom">;
type PreviewTarget = {
  anchor: HTMLElement | null;
  kind: "link" | "annotation" | "footnote";
};

function normalizedTitle(value: string) {
  return value.trim().replace(/\s+/g, " ").toLocaleLowerCase();
}

/** Installs inert rendered content while retaining the shared Document CSS owner. */
export function populatePreviewDocument(body: HTMLElement, preview: LinkPreview) {
  body.innerHTML = preview.htmlBody;
  sanitizePreviewDocument(body);
  localizeRenderedInterface(body);
  renderPreviewMathNodes(body);
  const firstHeading = body.querySelector<HTMLElement>(":scope > h1:first-child");
  if (firstHeading && normalizedTitle(firstHeading.textContent ?? "") === normalizedTitle(preview.title)) {
    firstHeading.remove();
  }
}

export interface PreviewPopoverController {
  readonly extension: Extension;
  hide(): void;
  canShowAtSelection(): boolean;
  showAtSelection(): boolean;
}

/** Owns cached-link, footnote, and source-owned annotation previews without owning source. */
export function createPreviewPopoverController(
  options: {
    nativeFloating: NativePreviewPort;
    previews(): readonly LinkPreview[];
    footnotes(): FootnotePresentation;
    holdOpenForPerformancePreview(): boolean;
    renderFootnoteContent(content: string, parent: HTMLElement): void;
  },
): PreviewPopoverController {
  let nativeID = 0;
  let presentationRevision = 0;
  let nativeHovered = false;
  let editor: EditorView | null = null;
  let root: HTMLElement | null = null;
  let title: HTMLElement | null = null;
  let metadata: HTMLElement | null = null;
  let body: HTMLElement | null = null;
  let showTimer: number | undefined;
  let hideTimer: number | undefined;
  let target: PreviewTarget | null = null;
  let hoveredLink: HTMLElement | null = null;
  let armedLink: HTMLElement | null = null;
  let activeAnnotationButton: HTMLButtonElement | null = null;
  let pinnedAnnotationButton: HTMLButtonElement | null = null;
  let activeFootnoteButton: HTMLButtonElement | null = null;

  function annotationTarget(button: HTMLButtonElement) {
    return button.dataset.linkAnnotationTarget?.trim() || localized("linked note");
  }

  function setAnnotationExpanded(button: HTMLButtonElement, expanded: boolean) {
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    button.setAttribute(
      "aria-label",
      localizedTemplate(expanded ? "Hide Link Annotation for {title}" : "Show Link Annotation for {title}",
        {title: annotationTarget(button)}),
    );
  }

  function setFootnoteExpanded(button: HTMLButtonElement, expanded: boolean) {
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
  }

  function hasPinnedPreview() {
    return pinnedAnnotationButton !== null;
  }

  function setArmedLink(next: HTMLElement | null) {
    if (armedLink === next) return;
    armedLink?.classList.remove("scholium-link-preview-armed");
    armedLink = next;
    armedLink?.classList.add("scholium-link-preview-armed");
  }

  function clearPresentation() {
    presentationRevision += 1;
    nativeHovered = false;
    options.nativeFloating.hide(nativeID);
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = null;
    pinnedAnnotationButton = null;
    activeFootnoteButton = null;
    if (root) {
      root.hidden = true;
      root.style.visibility = "";
    }
    if (title) title.textContent = "";
    if (metadata) metadata.textContent = "";
    body?.replaceChildren();
  }

  function hide(retainHoveredLink = false) {
    clearPresentation();
    window.clearTimeout(showTimer);
    window.clearTimeout(hideTimer);
    showTimer = undefined;
    hideTimer = undefined;
    target = null;
    if (!retainHoveredLink) hoveredLink = null;
    setArmedLink(null);
  }

  /** A target owns both pending intent and the displayed content, never its predecessor's. */
  function setTarget(next: PreviewTarget) {
    cancelHide();
    if (target?.anchor === next.anchor && target.kind === next.kind) return false;
    window.clearTimeout(showTimer);
    showTimer = undefined;
    clearPresentation();
    target = next;
    return true;
  }

  function cancelHide() {
    window.clearTimeout(hideTimer);
    hideTimer = undefined;
  }

  function scheduleHide() {
    if (hasPinnedPreview() || nativeHovered || options.holdOpenForPerformancePreview()) return;
    window.clearTimeout(hideTimer);
    hideTimer = window.setTimeout(hide, 180);
  }

  function position(anchor: PreviewAnchorRect, startedAt?: number) {
    if (!editor || !root) return;
    if (editor.composing) { hide(); return; }
    root.hidden = false;
    nativeID = options.nativeFloating.show(previewSurface(anchor, root), {
      dismiss: hide,
      enter: () => { nativeHovered = true; cancelHide(); },
      leave: () => { nativeHovered = false; scheduleHide(); },
    });
    if (startedAt !== undefined) {
      const activeEditor = editor;
      const revision = presentationRevision;
      scheduleAfterNextPaint(() => {
        if (revision !== presentationRevision) return;
        recordEditorMetric("cached-preview", startedAt, {documentLength: activeEditor.state.doc.length});
      });
    }
  }

  function showLinkPreview(
    preview: LinkPreview, anchor: PreviewAnchorRect, startedAt: number,
    element: HTMLElement | null = null,
  ) {
    if (!editor || !root || !title || !metadata || !body) return;
    setTarget({anchor: element, kind: "link"});
    if (element && target?.anchor === element && root && !root.hidden) return;
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = null;
    activeFootnoteButton = null;
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
    setTarget({anchor: button, kind: "annotation"});
    if (!root.hidden) return true;
    const template = annotationTemplate(button);
    if (!template) { hide(); return false; }
    if (activeAnnotationButton && activeAnnotationButton !== button) {
      setAnnotationExpanded(activeAnnotationButton, false);
    }
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = button;
    activeFootnoteButton = null;
    setAnnotationExpanded(button, true);
    title.textContent = annotationTarget(button);
    metadata.textContent = localized("Link Annotation");
    metadata.hidden = false;
    body.replaceChildren(template.content.cloneNode(true));
    sanitizePreviewDocument(body);
    renderPreviewMathNodes(body);
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
    setTarget({anchor: button, kind: "footnote"});
    if (button && !root.hidden) return true;
    const definition = options.footnotes().definitions.find((candidate) =>
      candidate.identifier === reference.identifier);
    const content = definition?.content.trim() ?? "";
    if (!content) { hide(); return false; }
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton && activeFootnoteButton !== button) {
      setFootnoteExpanded(activeFootnoteButton, false);
    }
    activeAnnotationButton = null;
    activeFootnoteButton = button;
    if (button) setFootnoteExpanded(button, true);
    title.textContent = localizedTemplate("Footnote {ordinal}", {ordinal: reference.ordinal});
    metadata.textContent = "";
    metadata.hidden = true;
    body.replaceChildren();
    options.renderFootnoteContent(content, body);
    sanitizePreviewDocument(body);
    renderPreviewMathNodes(body);
    position(anchor);
    return true;
  }

  function showFootnote(button: HTMLButtonElement) {
    const reference = footnoteReferenceFor(button);
    if (!reference) { hide(); return false; }
    return showFootnoteReference(reference, button.getBoundingClientRect(), button);
  }

  function selectionPreview():
    | {kind: "footnote"; reference: FootnoteReferencePresentation; anchor: PreviewAnchorRect}
    | {kind: "link"; preview: LinkPreview; anchor: PreviewAnchorRect}
    | null {
    if (!editor || editor.composing) return null;
    const head = editor.state.selection.main.head;
    const coords = editor.coordsAtPos(head);
    if (!coords) return null;
    const footnote = options.footnotes().references.find((candidate) =>
      head >= candidate.from && head < candidate.to);
    if (footnote && options.footnotes().definitions.some((definition) =>
      definition.identifier === footnote.identifier && definition.content.trim())) {
      return {kind: "footnote", reference: footnote, anchor: coords};
    }
    const preview = options.previews().find((candidate) => head >= candidate.from && head < candidate.to);
    return preview ? {kind: "link", preview, anchor: coords} : null;
  }

  function canShowAtSelection() { return selectionPreview() !== null; }

  function showAtSelection() {
    if (!editor || editor.composing) return false;
    const startedAt = performance.now();
    const selected = selectionPreview();
    if (selected?.kind === "footnote") {
      hide();
      return showFootnoteReference(selected.reference, selected.anchor);
    }
    if (selected?.kind === "link") {
      hide();
      showLinkPreview(selected.preview, selected.anchor, startedAt);
      return true;
    }
    hide();
    announceEditorMessage(
      editor.contentDOM,
      localized("No preview is available at the insertion point."),
    );
    return false;
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
    if (!setTarget({anchor, kind})) return;
    if (kind === "link" && !previewForAnchor(anchor)) return;
    showTimer = window.setTimeout(() => {
      if (target?.anchor !== anchor || target.kind !== kind) return;
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
        showLinkPreview(preview, anchor.getBoundingClientRect(), performance.now(), anchor);
      }
    }, 300);
  }

  const handlePointerMove = (event: PointerEvent) => {
    if (editor?.composing) { hide(); return; }
    const annotation = annotationButtonAt(event.target);
    const footnote = footnoteButtonAt(event.target);
    const link = linkAnchorAt(event.target);
    hoveredLink = link;
    if (hasPinnedPreview()
        && annotation !== pinnedAnnotationButton) {
      setArmedLink(null);
      return;
    }
    // Pointer events carry the current modifier state even when its key-up was
    // delivered in the native preview window rather than this document.
    const modifierActive = event.metaKey && !event.ctrlKey;
    setArmedLink(modifierActive ? link : null);
    const anchor = annotation ?? footnote ?? (modifierActive ? link : null);
    if (!anchor) {
      if (target) scheduleHide();
      return;
    }
    scheduleShow(anchor, annotation ? "annotation" : footnote ? "footnote" : "link");
  };
  const handleKeyUp = (event: KeyboardEvent) => {
    if (event.key !== "Meta" && event.key !== "Control") return;
    updateCommandIntent(event);
  };
  const handleCompositionStart = () => hide();
  function updateCommandIntent(event: KeyboardEvent) {
    const active = event.metaKey && !event.ctrlKey && !event.isComposing
      && event.keyCode !== 229 && !editor?.composing && !hasPinnedPreview();
    setArmedLink(active ? hoveredLink : null);
    if (active && hoveredLink) scheduleShow(hoveredLink, "link");
    else if (target?.kind === "link" && !nativeHovered) hide(true);
  }
  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.isComposing || event.keyCode === 229) return;
    if (event.key === "Escape" && root && !root.hidden) {
      hide();
      return;
    }
    if (event.key !== "Meta" && event.key !== "Control") return;
    updateCommandIntent(event);
  };
  const handleFocusIn = (event: FocusEvent) => {
    const button = annotationButtonAt(event.target) ?? footnoteButtonAt(event.target);
    if (!button) return;
    cancelHide();
    window.clearTimeout(showTimer);
    if (button.matches(".footnote-reference")) showFootnote(button);
    else showAnnotation(button);
  };
  const handleFocusOut = (event: FocusEvent) => {
    const button = annotationButtonAt(event.target) ?? footnoteButtonAt(event.target);
    if (!button) return;
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
      window.clearTimeout(showTimer);
      if (showAnnotation(button)) pinnedAnnotationButton = button;
      return;
    }
    const footnote = footnoteButtonAt(event.target);
    if (footnote) {
      event.preventDefault();
      event.stopPropagation();
      const reference = footnoteReferenceFor(footnote);
      const from = reference?.definitionContentFrom;
      hide();
      if (!editor || editor.composing || from === null || from === undefined
          || from < 0 || from > editor.state.doc.length) return;
      editor.dispatch({selection: {anchor: from}, scrollIntoView: true, userEvent: "select"});
      editor.focus();
      return;
    }
    if (hasPinnedPreview()) hide();
  };
  const handleMouseDown = (event: MouseEvent) => {
    if (event.button !== 0 || !footnoteButtonAt(event.target)) return;
    // Keep pointer activation on the same explicit click route as keyboard
    // activation; pressing the marker must not start a CodeMirror text drag.
    event.preventDefault();
    event.stopPropagation();
  };
  const handleViewportExit = () => {
    hoveredLink = null;
    hide();
  };
  const handlePointerLeave = () => {
    hoveredLink = null;
    setArmedLink(null);
    if (target?.kind === "link") scheduleHide();
  };
  const handleWindowBlur = () => {
    handlePointerLeave();
    if (!nativeHovered) hide();
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
    // Detached content builder; the native floating container owns presentation.
    document.addEventListener("pointermove", handlePointerMove, {passive: true});
    document.addEventListener('focusin', handleFocusIn);
    document.addEventListener('focusout', handleFocusOut);
    document.addEventListener("click", handleClick);
    document.addEventListener("mousedown", handleMouseDown, true);
    document.addEventListener("keyup", handleKeyUp);
    document.addEventListener("keydown", handleKeyDown);
    document.addEventListener("compositionstart", handleCompositionStart);
    view.contentDOM.addEventListener("pointerleave", handlePointerLeave);
    view.scrollDOM.addEventListener("scroll", handleViewportExit, {passive: true});
    window.addEventListener("resize", handleViewportExit);
    window.addEventListener("blur", handleWindowBlur);
  }

  function unmount(view: EditorView) {
    if (editor !== view) return;
    hide();
    document.removeEventListener("pointermove", handlePointerMove);
    document.removeEventListener('focusin', handleFocusIn);
    document.removeEventListener('focusout', handleFocusOut);
    document.removeEventListener("click", handleClick);
    document.removeEventListener("mousedown", handleMouseDown, true);
    document.removeEventListener("keyup", handleKeyUp);
    document.removeEventListener("keydown", handleKeyDown);
    document.removeEventListener("compositionstart", handleCompositionStart);
    view.contentDOM.removeEventListener("pointerleave", handlePointerLeave);
    view.scrollDOM.removeEventListener("scroll", handleViewportExit);
    window.removeEventListener("resize", handleViewportExit);
    window.removeEventListener("blur", handleWindowBlur);
    root = null;
    title = null;
    metadata = null;
    body = null;
    editor = null;
    hoveredLink = null;
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

  return {extension, hide, canShowAtSelection, showAtSelection};
}

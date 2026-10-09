interface ImagePreviewActions {
  label(name: string): string;
  preview(target: string): void;
  contextMenu(target: string, clientX: number, clientY: number): void;
}

const imageSelector = "img.scholium-embedded-image[data-scholium-image-target]";

/** The renderer supplies parser-owned targets. Native code alone resolves the
 * original attachment; the thumbnail's data URL never grants file access. */
export function installReviewImageActivation(root: HTMLElement, actions: ImagePreviewActions | null) {
  let spaceTarget: {image: HTMLImageElement; target: string} | null = null;
  let pointer: {image: HTMLImageElement; target: string; x: number; y: number; released: boolean} | null = null;
  const targetFor = (image: HTMLImageElement) => {
    if (!root.contains(image) || !image.matches(imageSelector)
        || !image.complete || image.naturalWidth <= 0 || image.naturalHeight <= 0) return null;
    const target = image.dataset.scholiumImageTarget;
    return target && new TextEncoder().encode(target).length <= 8_192 ? target : null;
  };
  const imageFor = (target: EventTarget | null): HTMLImageElement | null => {
    if (!(target instanceof Element)) return null;
    if (target.matches(imageSelector)) return target as HTMLImageElement;
    // Keyboard context-menu activation is dispatched to the focused link.
    const link = target.closest("a");
    const images = link?.querySelectorAll<HTMLImageElement>(imageSelector);
    return images?.length === 1 ? images[0] : null;
  };
  const refreshImage = (image: HTMLImageElement) => {
    const target = targetFor(image);
    const block = image.dataset.scholiumImageLayout === "block";
    image.classList.toggle("scholium-embedded-image-block", block);
    if (target) image.style.setProperty("--scholium-image-aspect-ratio", String(image.naturalWidth / image.naturalHeight));
    else image.style.removeProperty("--scholium-image-aspect-ratio");
    const directPreview = Boolean(actions && target && !image.closest("a"));
    image.classList.toggle("scholium-image-preview", directPreview);
    if (directPreview) {
      let filename = target!.slice(target!.lastIndexOf("/") + 1);
      try { filename = decodeURIComponent(filename); } catch { /* Keep authored spelling for the label. */ }
      const alt = image.alt.trim();
      const name = alt && alt !== filename ? `${alt} (${filename})` : filename;
      image.setAttribute("role", "button");
      image.setAttribute("tabindex", "0");
      image.setAttribute("aria-label", actions!.label(name));
    } else {
      image.removeAttribute("role");
      image.removeAttribute("tabindex");
      image.removeAttribute("aria-label");
      if (spaceTarget?.image === image) spaceTarget = null;
      if (pointer?.image === image) pointer = null;
    }
  };
  const refresh = () => root.querySelectorAll<HTMLImageElement>(imageSelector).forEach(refreshImage);
  const loadChanged = (event: Event) => {
    const image = imageFor(event.target);
    if (image) refreshImage(image);
  };
  const unmodified = (event: MouseEvent | KeyboardEvent) =>
    !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
  const mouseDown = (event: MouseEvent) => {
    pointer = null;
    const image = imageFor(event.target);
    const target = image && targetFor(image);
    const contextClick = event.button === 2 || (event.button === 0 && event.ctrlKey
      && !event.metaKey && !event.altKey && !event.shiftKey);
    if (actions && image && target
        && (contextClick || (event.button === 0 && unmodified(event) && !image.closest("a")))) {
      // Opening a preview preserves the reader's selection and focus owner.
      event.preventDefault();
      if (!contextClick) pointer = {image, target, x: event.clientX, y: event.clientY, released: false};
    }
  };
  const pointerMatches = (event: MouseEvent) => pointer && event.target === pointer.image
    && targetFor(pointer.image) === pointer.target
    && Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y) <= 4;
  const mouseMove = (event: MouseEvent) => { if (pointer && !pointerMatches(event)) pointer = null; };
  const mouseUp = (event: MouseEvent) => {
    if (event.button === 0 && pointerMatches(event)) pointer!.released = true;
    else pointer = null;
  };
  const cancelPointer = () => { pointer = null; };
  const mouseOut = (event: MouseEvent) => {
    if (pointer && event.target === pointer.image) pointer = null;
  };
  const click = (event: MouseEvent) => {
    const started = pointer;
    const completed = pointerMatches(event);
    pointer = null;
    const image = imageFor(event.target);
    const target = image && targetFor(image);
    if (!actions || !image || !target || image.closest("a") || event.button !== 0 || !unmodified(event)) return;
    // Accessibility activation has no pointer gesture. A pointer click must
    // finish on its original rendered image without becoming a drag.
    if (event.detail !== 0 && (!completed || !started?.released)) return;
    event.preventDefault();
    event.stopPropagation();
    actions.preview(target);
  };
  const openContextMenu = (image: HTMLImageElement, target: string, clientX = 0, clientY = 0) => {
    if (clientX === 0 && clientY === 0) {
      const bounds = image.getBoundingClientRect();
      clientX = bounds.left + bounds.width / 2;
      clientY = bounds.top + bounds.height / 2;
    }
    actions?.contextMenu(target, clientX, clientY);
  };
  const keyDown = (event: KeyboardEvent) => {
    pointer = null;
    const image = imageFor(event.target);
    const target = image && targetFor(image);
    if (!actions || !image || !target || event.isComposing || event.keyCode === 229) return;
    if (!event.metaKey && !event.ctrlKey && !event.altKey
        && (event.key === "ContextMenu" || (event.key === "F10" && event.shiftKey))) {
      event.preventDefault();
      event.stopPropagation();
      if (!event.repeat) openContextMenu(image, target);
      return;
    }
    if (image.closest("a") || !unmodified(event)) return;
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    event.stopPropagation();
    if (event.repeat) return;
    if (event.key === "Enter") actions.preview(target);
    else spaceTarget = {image, target};
  };
  const keyUp = (event: KeyboardEvent) => {
    if (event.key !== " ") return;
    const started = spaceTarget;
    spaceTarget = null;
    if (!actions || !started || event.target !== started.image || event.isComposing || !unmodified(event)) return;
    event.preventDefault();
    event.stopPropagation();
    const target = targetFor(started.image);
    if (target === started.target) actions.preview(target);
  };
  const focusOut = () => { spaceTarget = null; pointer = null; };
  const contextMenu = (event: MouseEvent) => {
    const image = imageFor(event.target);
    const target = image && targetFor(image);
    if (!actions || !image || !target) return;
    event.preventDefault();
    event.stopPropagation();
    openContextMenu(image, target, event.clientX, event.clientY);
  };
  refresh();
  root.addEventListener("load", loadChanged, true);
  root.addEventListener("error", loadChanged, true);
  root.addEventListener("mousedown", mouseDown);
  root.addEventListener("mousemove", mouseMove);
  root.addEventListener("mouseup", mouseUp);
  root.addEventListener("mouseout", mouseOut);
  root.addEventListener("dragstart", cancelPointer);
  root.addEventListener("pointercancel", cancelPointer);
  root.addEventListener("click", click);
  root.addEventListener("keydown", keyDown);
  root.addEventListener("keyup", keyUp);
  root.addEventListener("focusout", focusOut);
  root.addEventListener("contextmenu", contextMenu);
  return {
    refresh,
    destroy() {
      spaceTarget = null;
      pointer = null;
      root.removeEventListener("load", loadChanged, true);
      root.removeEventListener("error", loadChanged, true);
      root.removeEventListener("mousedown", mouseDown);
      root.removeEventListener("mousemove", mouseMove);
      root.removeEventListener("mouseup", mouseUp);
      root.removeEventListener("mouseout", mouseOut);
      root.removeEventListener("dragstart", cancelPointer);
      root.removeEventListener("pointercancel", cancelPointer);
      root.removeEventListener("click", click);
      root.removeEventListener("keydown", keyDown);
      root.removeEventListener("keyup", keyUp);
      root.removeEventListener("focusout", focusOut);
      root.removeEventListener("contextmenu", contextMenu);
    },
  };
}

/**
 * Typed native presentation ports. The native host may arbitrate which one is
 * visible, but preview, completion, and selection never share a payload with
 * unrelated fields or callbacks.
 */
export interface NativePreviewSurface {
  id: number;
  left: number;
  top: number;
  bottom: number;
  html: string;
  css: string;
  imageResourceKeys: string[];
}

export interface NativeSuggestionSurface {
  id: number;
  left: number;
  top: number;
  bottom: number;
  items: Array<{label: string; detail: string; disabled: boolean}>;
  selected: number;
}

export interface NativeSelectionSurface {
  id: number;
  left: number;
  top: number;
  bottom: number;
  utf16Count: number;
}

export type NativeFloatingEvent =
  | {type: "previewSurface"; surface: NativePreviewSurface}
  | {type: "previewFailure"; id: number; reason: "size"}
  | {type: "suggestionSurface"; surface: NativeSuggestionSurface}
  | {type: "selectionSurface"; surface: NativeSelectionSurface}
  | {type: "dismissSurface"; kind: NativeFloatingKind; id: number};

export type NativeFloatingKind = "preview" | "suggestions" | "selection";

interface PreviewCallbacks {
  dismiss(): void;
  enter?(): void;
  leave?(): void;
}

interface SuggestionCallbacks {
  dismiss(): void;
  select?(index: number): void;
  choose?(index: number): boolean | void;
}

interface SelectionCallbacks {
  dismiss(): void;
  choose?(index: number): boolean | void;
}

export interface NativePreviewPort {
  show(surface: Omit<NativePreviewSurface, "id">, callbacks: PreviewCallbacks): number;
  hide(id: number): void;
}

export interface NativeSuggestionPort {
  show(surface: Omit<NativeSuggestionSurface, "id">, callbacks: SuggestionCallbacks): number;
  hide(id: number): void;
}

export interface NativeSelectionPort {
  show(surface: Omit<NativeSelectionSurface, "id">, callbacks: SelectionCallbacks): number;
  hide(id: number): void;
}

export interface NativeFloatingPorts {
  preview: NativePreviewPort;
  suggestions: NativeSuggestionPort;
  selection: NativeSelectionPort;
  forOwner(post: (event: NativeFloatingEvent) => void): NativeFloatingPorts;
}

type ActivePresentation = {
  kind: NativeFloatingKind;
  id: number;
  dismiss(): void;
  event(id: number, action: string, index: number): boolean;
  owner: (event: NativeFloatingEvent) => void;
};

/**
 * Creates typed presentation ports sharing only native-host arbitration and
 * the bounded event route back into the active CodeMirror/reader owner.
 */
export function createNativeFloatingPorts(
  post: (event: NativeFloatingEvent) => void,
): NativeFloatingPorts {
  let serial = 0;
  let active: ActivePresentation | null = null;

  function activate(
    kind: NativeFloatingKind,
    callbacks: {dismiss(): void},
    event: (id: number, action: string, index: number) => boolean,
    owner: (event: NativeFloatingEvent) => void,
  ) {
    if (active && (active.kind !== kind || active.owner !== owner)) active.dismiss();
    const id = ++serial;
    active = {kind, id, dismiss: callbacks.dismiss, event, owner};
    return id;
  }

  function portsForOwner(ownerPost: (event: NativeFloatingEvent) => void): NativeFloatingPorts {
    function hide(kind: NativeFloatingKind, id: number) {
      if (active?.kind !== kind || active.id !== id || active.owner !== ownerPost) return;
      ownerPost({type: "dismissSurface", kind, id});
      active = null;
    }

    const preview: NativePreviewPort = {
      show(surface, callbacks) {
        const id = activate("preview", callbacks, (currentID, action, _index) => {
          if (currentID !== id) return false;
          if (action === "enter") callbacks.enter?.();
          else if (action === "leave") callbacks.leave?.();
          else if (action === "dismiss") callbacks.dismiss();
          else return false;
          return true;
        }, ownerPost);
        const bounded = (text: string, maximum: number) => text.length <= maximum
          && (text.length <= maximum / 3 || new TextEncoder().encode(text).length <= maximum);
        const payload = {...surface, id};
        const keys = surface.imageResourceKeys;
        if (keys.length > 8192 || new Set(keys).size !== keys.length
            || keys.some(key => !key || key.length > 16_384)
            || !bounded(surface.html, 500_000) || !bounded(surface.css, 900_000)
            || new TextEncoder().encode(JSON.stringify(payload).replaceAll('/', '\\/')).length > 1_500_000) {
          active = null;
          ownerPost({type: "previewFailure", id, reason: "size"});
          callbacks.dismiss();
          return id;
        }
        ownerPost({type: "previewSurface", surface: payload});
        return id;
      },
      hide(id) { hide("preview", id); },
    };

    const suggestions: NativeSuggestionPort = {
      show(surface, callbacks) {
        const id = activate("suggestions", callbacks, (currentID, action, index) => {
          if (currentID !== id || !Number.isInteger(index)) return false;
          if (action === "dismiss") callbacks.dismiss();
          else if (action === "select" && index >= 0 && index < surface.items.length) callbacks.select?.(index);
          else if (action === "choose" && index >= 0 && index < surface.items.length) {
            if (surface.items[index].disabled) return false;
            return callbacks.choose?.(index) !== false;
          } else return false;
          return true;
        }, ownerPost);
        ownerPost({type: "suggestionSurface", surface: {...surface, id}});
        return id;
      },
      hide(id) { hide("suggestions", id); },
    };

    const selection: NativeSelectionPort = {
      show(surface, callbacks) {
        const id = activate("selection", callbacks, (currentID, action, index) => {
          if (currentID !== id) return false;
          if (action === "dismiss") callbacks.dismiss();
          else if (action === "choose" && index === 0) return callbacks.choose?.(index) !== false;
          else return false;
          return true;
        }, ownerPost);
        ownerPost({type: "selectionSurface", surface: {...surface, id}});
        return id;
      },
      hide(id) { hide("selection", id); },
    };
    return {preview, suggestions, selection, forOwner: portsForOwner};
  }

  const event = (id: number, action: string, index: number) =>
    active?.id === id ? active.event(id, action, index) : false;
  (window as Window & {scholiumNativeFloatingEvent?: typeof event})
    .scholiumNativeFloatingEvent = event;

  return portsForOwner(post);
}

export function previewSurface(
  anchor: Pick<DOMRect, "left" | "top" | "bottom">,
  root: HTMLElement,
): Omit<NativePreviewSurface, "id"> {
  // The detached DOM is a content builder, never another visible or accessible panel.
  // Native loads this inert projection under its own deny-by-default CSP.
  // This detached builder carries admitted keys, never another copy of the
  // current Note's raster bytes. Peer preview HTML uses inline delivery and
  // deliberately has no current-Note resource key.
  const imageResourceKeys = new Set<string>();
  for (const image of root.querySelectorAll<HTMLImageElement>(
    'img.scholium-embedded-image[data-scholium-image-resource]')) {
    if (image.closest('.scholium-embedded-note')) continue;
    const key = image.getAttribute('data-scholium-image-resource')!;
    imageResourceKeys.add(key);
    image.removeAttribute('src');
  }
  const css = Array.from(document.querySelectorAll("style"), node => node.textContent ?? "").join("\n");
  return {
    left: anchor.left,
    top: anchor.top,
    bottom: anchor.bottom,
    html: root.innerHTML,
    css,
    imageResourceKeys: [...imageResourceKeys],
  };
}

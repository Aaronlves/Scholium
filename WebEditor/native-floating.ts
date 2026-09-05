/** Read-only presentation projection. Editing, selection and keyboard state stay in CodeMirror. */
export interface NativeFloatingPayload {
  id: number;
  kind: "preview" | "suggestions" | "hidden";
  left: number;
  top: number;
  bottom: number;
  html: string;
  css: string;
  items: Array<{label: string; detail: string}>;
  selected: number;
}
interface FloatingCallbacks {
  dismiss(): void;
  enter?(): void;
  leave?(): void;
  select?(index: number): void;
  choose?(index: number): void;
}
export function createNativeFloatingBridge(post: (surface: NativeFloatingPayload) => void) {
  let serial = 0;
  let current: {surface: NativeFloatingPayload; callbacks: FloatingCallbacks} | null = null;
  const bridge = {
    show(surface: Omit<NativeFloatingPayload, "id">, callbacks: FloatingCallbacks) {
      if (current && current.surface.kind !== surface.kind) current.callbacks.dismiss();
      const id = ++serial;
      current = {surface: {...surface, id}, callbacks};
      post(current.surface);
      return id;
    },
    hide(id: number) {
      if (current?.surface.id !== id) return;
      post({...current.surface, kind: "hidden", html: "", css: "", items: [], selected: -1});
      current = null;
    },
    event(id: number, action: string, index: number) {
      if (current?.surface.id !== id) return false;
      const callbacks = current.callbacks;
      if (action === "enter") callbacks.enter?.();
      else if (action === "leave") callbacks.leave?.();
      else if (action === "dismiss") callbacks.dismiss();
      else if ((action === "select" || action === "choose") && Number.isInteger(index)
        && current.surface.kind === "suggestions"
        && index >= 0 && index < current.surface.items.length) {
        if (action === "select") callbacks.select?.(index);
        else callbacks.choose?.(index);
      }
      else return false;
      return true;
    },
  };
  (window as Window & {scholiumNativeFloatingEvent?: typeof bridge.event})
    .scholiumNativeFloatingEvent = bridge.event;
  return bridge;
}
export type NativeFloatingBridge = ReturnType<typeof createNativeFloatingBridge>;

export function previewSurface(anchor: Pick<DOMRect, "left" | "top" | "bottom">, root: HTMLElement) {
  // The detached DOM is a content builder, never another visible or accessible panel.
  // Native loads this inert projection under its own deny-by-default CSP.
  const css = Array.from(document.querySelectorAll("style"), node => node.textContent ?? "").join("\n");
  return {
    kind: "preview" as const, left: anchor.left, top: anchor.top, bottom: anchor.bottom,
    html: root.innerHTML, css, items: [], selected: -1,
  };
}

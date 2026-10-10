import type {NativeSelectionPort} from "./native-floating";

export interface SelectionActionTarget {
  key: string;
  anchor: Pick<DOMRect, "left" | "top" | "bottom">;
  utf16Count: number;
}

/** The document owns selection; native owns the one floating control. */
export function createSelectionActions(
  floating: NativeSelectionPort,
  current: () => SelectionActionTarget | null,
  currentKey: () => string | null,
) {
  let id: number | null = null;
  let key: string | null = null;
  let dismissed: string | null = null;
  let presentationRevision = 0;
  function hide() {
    if (id !== null) floating.hide(id);
    id = null;
    key = null;
  }
  function dismissForScroll() {
    const visible = id !== null;
    if (key !== null) dismissed = key;
    hide();
    return visible;
  }
  function dismiss() {
    presentationRevision += 1;
    return dismissForScroll();
  }
  function update(target = current()) {
    if (!target) {
      hide();
      if (currentKey() === null) dismissed = null;
      return;
    }
    if (target.key === key || target.key === dismissed) return;
    hide();
    key = target.key;
    id = floating.show({...target.anchor, utf16Count: target.utf16Count}, {
      dismiss,
      choose: () => currentKey() === target.key,
    });
  }
  return {
    get surfaceID() { return id; },
    get presentationRevision() { return presentationRevision; },
    dismiss,
    dismissForScroll,
    dismissForKey(event: Pick<KeyboardEvent, "key" | "isComposing">) {
      // Let the existing Tab route run; changed selections dismiss independently.
      if (event.key === "Tab" && !event.isComposing) {
        presentationRevision += 1;
        return false;
      }
      return dismiss();
    },
    presentCurrent(target = current()) {
      // A named native command may reopen the current exact selection after
      // Escape or scrolling; automatic updates continue to respect dismissal.
      dismissed = null;
      hide();
      update(target);
      return id !== null;
    },
    update,
  };
}

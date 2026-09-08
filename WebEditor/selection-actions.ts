import type {NativeFloatingBridge} from "./native-floating";

export interface SelectionActionTarget {
  key: string;
  anchor: Pick<DOMRect, "left" | "top" | "bottom">;
}
/** The document owns selection; native owns the one floating control. */
export function createSelectionActions(
  floating: NativeFloatingBridge,
  current: () => SelectionActionTarget | null,
) {
  let id: number | null = null;
  let key: string | null = null;
  let dismissed: string | null = null;
  function hide() {
    if (id !== null) floating.hide(id);
    id = null;
    key = null;
  }
  function dismiss() {
    const visible = id !== null;
    if (key !== null) dismissed = key;
    hide();
    return visible;
  }
  return {
    dismiss,
    update(target = current()) {
      if (!target) { hide(); dismissed = null; return; }
      if (target.key === key || target.key === dismissed) return;
      hide();
      key = target.key;
      id = floating.show({kind: "selection", ...target.anchor,
        html: "", css: "", items: [], selected: -1}, {
        dismiss,
        choose: () => {
          const valid = current()?.key === target.key;
          return valid;
        },
      });
    },
  };
}

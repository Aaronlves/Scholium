import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingPorts, type NativeFloatingEvent} from "../native-floating";
import {createSelectionActions, type SelectionActionTarget} from "../selection-actions";
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
describe("source selection action", () => {
  it("rejects an old selection and retains dismissal until selection changes", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    let target: SelectionActionTarget | null = {key: "revision:1:2", anchor: {left: 1, top: 2, bottom: 3}};
    const actions = createSelectionActions(ports.selection, () => target);
    actions.update();
    const initialEvent = sent.at(-1)!;
    const first = initialEvent.type === "selectionSurface" ? initialEvent.surface.id : 0;
    target = {...target, key: "revision:4:5"};
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(first, "choose", 0)).toBe(false);
    actions.update();
    const currentEvent = sent.at(-1)!;
    const current = currentEvent.type === "selectionSurface" ? currentEvent.surface.id : 0;
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(first, "choose", 0)).toBe(false);
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(current, "choose", 0)).toBe(true);
    const count = sent.length;
    actions.update();
    expect(sent).toHaveLength(count);
    target = null; actions.update();
    target = {key: "revision:4:5", anchor: {left: 1, top: 2, bottom: 3}};
    actions.update();
    expect(sent.at(-1)!.type).toBe("selectionSurface");
    expect(actions.dismiss()).toBe(true);
    expect(sent.at(-1)!.type).toBe("dismissSurface");
    expect(actions.dismiss()).toBe(false);
    const dismissedCount = sent.length;
    actions.update();
    expect(sent).toHaveLength(dismissedCount);
  });
});

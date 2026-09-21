import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingPorts, type NativeFloatingEvent} from "../native-floating";

afterEach(() => vi.unstubAllGlobals());

describe("typed native floating ports", () => {
  const suggestions = {
    left: 20, top: 30, bottom: 44,
    items: [{label: "Date", detail: ""}], selected: 0,
  };

  it("rejects stale and out-of-range suggestion activation", () => {
    vi.stubGlobal("window", {});
    const choose = vi.fn(), select = vi.fn(), dismiss = vi.fn();
    const ports = createNativeFloatingPorts(() => {});
    const oldID = ports.suggestions.show(suggestions, {choose, select, dismiss});
    const newID = ports.suggestions.show(suggestions, {choose, select, dismiss});
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(oldID, "choose", 0)).toBe(false);
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(newID, "choose", 1)).toBe(false);
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(newID, "choose", 0)).toBe(true);
    expect(choose).toHaveBeenCalledExactlyOnceWith(0);
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(oldID, "select", 0)).toBe(false);
    for (const index of [-1, 1, 0.5, NaN]) {
      expect((window as Window & {scholiumNativeFloatingEvent?: Function})
        .scholiumNativeFloatingEvent?.(newID, "select", index)).toBe(false);
    }
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(newID, "select", 0)).toBe(true);
    expect(select).toHaveBeenCalledExactlyOnceWith(0);
    expect(choose).toHaveBeenCalledTimes(1);
    expect(dismiss).not.toHaveBeenCalled();
  });

  it("accepts only the selection action's bounded inquiry", () => {
    vi.stubGlobal("window", {});
    const choose = vi.fn((_index: number) => true);
    const ports = createNativeFloatingPorts(() => {});
    const id = ports.selection.show({left: 20, top: 30, bottom: 44}, {choose, dismiss() {}});
    const event = (window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent!;
    for (const index of [-1, 1, 2, 3, 4, 0.5, NaN]) expect(event(id, "choose", index)).toBe(false);
    expect(event(id, "choose", 0)).toBe(true);
    expect(choose.mock.calls.map(call => call[0])).toEqual([0]);
    ports.selection.hide(id);
    expect(event(id, "choose", 1)).toBe(false);
  });

  it("uses typed dismissal events instead of an empty universal payload", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    const first = ports.suggestions.show(suggestions, {dismiss() {}});
    const second = ports.suggestions.show(suggestions, {dismiss() {}});
    ports.suggestions.hide(first);
    expect(sent).toHaveLength(2);
    ports.suggestions.hide(second);
    expect(sent.at(-1)).toEqual({type: "dismissSurface", kind: "suggestions", id: second});
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(second, "choose", 0)).toBe(false);
  });

  it("dismisses the previous contextual owner when another typed port opens", () => {
    vi.stubGlobal("window", {});
    const dismiss = vi.fn();
    const ports = createNativeFloatingPorts(() => {});
    ports.suggestions.show(suggestions, {dismiss});
    ports.preview.show(
      {left: 20, top: 30, bottom: 44, html: "<p>Preview</p>", css: ""},
      {dismiss() {}},
    );
    expect(dismiss).toHaveBeenCalledOnce();
  });
});

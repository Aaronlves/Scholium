import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingBridge, type NativeFloatingPayload} from "../native-floating";

afterEach(() => vi.unstubAllGlobals());
describe("native floating projection", () => {
  const suggestions = {
    kind: "suggestions" as const, left: 20, top: 30, bottom: 44,
    html: "", css: "", items: [{label: "Date", detail: ""}], selected: 0,
  };
  it("rejects stale and out-of-range pointer activation", () => {
    vi.stubGlobal("window", {});
    const choose = vi.fn(), select = vi.fn(), dismiss = vi.fn();
    const bridge = createNativeFloatingBridge(() => {});
    const oldID = bridge.show(suggestions, {choose, select, dismiss});
    const newID = bridge.show(suggestions, {choose, select, dismiss});
    expect(bridge.event(oldID, "choose", 0)).toBe(false);
    expect(bridge.event(newID, "choose", 1)).toBe(false);
    expect(bridge.event(newID, "choose", 0)).toBe(true);
    expect(choose).toHaveBeenCalledExactlyOnceWith(0);
    expect(bridge.event(oldID, "select", 0)).toBe(false);
    for (const index of [-1, 1, 0.5, NaN]) expect(bridge.event(newID, "select", index)).toBe(false);
    expect(bridge.event(newID, "select", 0)).toBe(true);
    expect(select).toHaveBeenCalledExactlyOnceWith(0);
    // Pointing changes only the candidate; it never accepts or dismisses it.
    expect(choose).toHaveBeenCalledTimes(1);
    expect(dismiss).not.toHaveBeenCalled();
  });
  it("lets a native command menu choose only its still-current source owner", () => {
    vi.stubGlobal("window", {});
    const bridge = createNativeFloatingBridge(() => {});
    const choose = vi.fn(() => true);
    const commands = {...suggestions, kind: "commands" as const, selected: -1};
    const old = bridge.show(commands, {choose, dismiss() {}});
    const current = bridge.show(commands, {choose, dismiss() {}});
    expect(bridge.event(old, "choose", 0)).toBe(false);
    expect(bridge.event(current, "select", 0)).toBe(false);
    expect(bridge.event(current, "choose", 1)).toBe(false);
    expect(bridge.event(current, "choose", 0)).toBe(true);
    choose.mockReturnValue(false);
    expect(bridge.event(current, "choose", 0)).toBe(false);
    bridge.hide(current);
    expect(bridge.event(current, "choose", 0)).toBe(false);
    expect(choose).toHaveBeenCalledTimes(2);
  });
  it("accepts only known selection inquiries and checks their current owner", () => {
    vi.stubGlobal("window", {});
    const choose = vi.fn((_index: number) => true);
    const bridge = createNativeFloatingBridge(() => {});
    const surface = {...suggestions, kind: "selection" as const, items: [], selected: -1};
    const id = bridge.show(surface, {choose, dismiss() {}});
    for (const index of [-1, 1, 2, 3, 4, 0.5, NaN]) expect(bridge.event(id, "choose", index)).toBe(false);
    for (const index of [0]) expect(bridge.event(id, "choose", index)).toBe(true);
    expect(choose.mock.calls.map(call => call[0])).toEqual([0]);
    bridge.hide(id);
    expect(bridge.event(id, "choose", 1)).toBe(false);
  });
  it("closes only the current projection with a bounded empty payload", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingPayload[] = [];
    const bridge = createNativeFloatingBridge(surface => sent.push(surface));
    const first = bridge.show(suggestions, {dismiss() {}});
    const second = bridge.show(suggestions, {dismiss() {}});
    bridge.hide(first);
    expect(sent).toHaveLength(2);
    bridge.hide(second);
    expect(sent.at(-1)).toMatchObject({id: second, kind: "hidden", items: [], selected: -1, html: "", css: ""});
    expect(bridge.event(second, "choose", 0)).toBe(false);
  });
  it("dismisses the previous contextual owner when another kind opens", () => {
    vi.stubGlobal("window", {});
    const dismiss = vi.fn();
    const bridge = createNativeFloatingBridge(() => {});
    bridge.show(suggestions, {dismiss});
    bridge.show({...suggestions, kind: "preview", items: [], selected: -1, html: "<p>Preview</p>"}, {dismiss() {}});
    expect(dismiss).toHaveBeenCalledOnce();
  });
});

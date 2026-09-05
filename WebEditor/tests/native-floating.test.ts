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
    const choose = vi.fn(), dismiss = vi.fn();
    const bridge = createNativeFloatingBridge(() => {});
    const oldID = bridge.show(suggestions, {choose, dismiss});
    const newID = bridge.show(suggestions, {choose, dismiss});
    expect(bridge.event(oldID, "choose", 0)).toBe(false);
    expect(bridge.event(newID, "choose", 1)).toBe(false);
    expect(bridge.event(newID, "choose", 0)).toBe(true);
    expect(choose).toHaveBeenCalledExactlyOnceWith(0);
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

import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingBridge, type NativeFloatingPayload} from "../native-floating";
import {createSelectionActions, type SelectionActionTarget} from "../selection-actions";
import {EditorState} from "@codemirror/state";
import type {EditorView} from "@codemirror/view";
import {createEditorScrollCoordinator} from "../scroll-coordinator";
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
describe("source selection action", () => {
  it("dismisses on scroll before the anchor report without changing the selection", () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {
      setTimeout, clearTimeout, requestAnimationFrame: () => 1,
    });
    const sent: NativeFloatingPayload[] = [];
    const bridge = createNativeFloatingBridge(surface => sent.push(surface));
    const actions = createSelectionActions(bridge, () => ({
      key: "revision:0:4", anchor: {left: 1, top: 2, bottom: 3},
    }));
    const state = EditorState.create({doc: "text", selection: {anchor: 0, head: 4}});
    const scrollDOM = Object.assign(new EventTarget(), {
      scrollTop: 40, scrollHeight: 200, clientHeight: 100,
    });
    const editor = {state, scrollDOM,
      lineBlockAtHeight: () => ({from: 0, to: 4, top: 0, height: 100}),
    } as unknown as EditorView;
    const post = vi.fn();
    createEditorScrollCoordinator(editor, {
      onScroll: () => actions.dismiss(), post, flushPresentationGeometry() {},
    });
    actions.update();
    const id = sent.at(-1)!.id;
    scrollDOM.dispatchEvent(new Event("scroll"));
    expect(sent.at(-1)!.kind).toBe("hidden");
    expect(bridge.event(id, "choose", 0)).toBe(false);
    expect(post).not.toHaveBeenCalled();
    vi.advanceTimersByTime(60);
    scrollDOM.dispatchEvent(new Event("scroll"));
    vi.advanceTimersByTime(119);
    expect(post).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(post).toHaveBeenCalledExactlyOnceWith(expect.objectContaining({fallbackFraction: 0.4}));
    expect(editor.state).toBe(state);
    actions.update();
    expect(sent.at(-1)!.kind).toBe("hidden");
  });
  it("rejects an old selection and retains dismissal until selection changes", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingPayload[] = [];
    const bridge = createNativeFloatingBridge(surface => sent.push(surface));
    let target: SelectionActionTarget | null = {key: "revision:1:2", anchor: {left: 1, top: 2, bottom: 3}};
    const actions = createSelectionActions(bridge, () => target);
    actions.update();
    const first = sent.at(-1)!.id;
    target = {...target, key: "revision:4:5"};
    expect(bridge.event(first, "choose", 0)).toBe(false);
    actions.update();
    const current = sent.at(-1)!.id;
    expect(bridge.event(first, "choose", 0)).toBe(false);
    expect(bridge.event(current, "choose", 0)).toBe(true);
    const count = sent.length;
    actions.update();
    expect(sent).toHaveLength(count);
    target = null; actions.update();
    target = {key: "revision:4:5", anchor: {left: 1, top: 2, bottom: 3}};
    actions.update();
    expect(sent.at(-1)!.kind).toBe("selection");
    expect(actions.dismiss()).toBe(true);
    expect(sent.at(-1)!.kind).toBe("hidden");
    expect(actions.dismiss()).toBe(false);
    const dismissedCount = sent.length;
    actions.update();
    expect(sent).toHaveLength(dismissedCount);
  });
});

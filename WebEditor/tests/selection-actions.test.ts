import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingPorts, type NativeFloatingEvent} from "../native-floating";
import {createSelectionActions, type SelectionActionTarget} from "../selection-actions";
import {EditorState} from "@codemirror/state";
import type {EditorView} from "@codemirror/view";
import {createEditorScrollCoordinator} from "../scroll-coordinator";
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
describe("source selection action", () => {
  it("dismisses on scroll before the anchor report without changing the selection", () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {
      setTimeout, clearTimeout,
      requestAnimationFrame: (callback: () => void) => setTimeout(callback, 16),
      cancelAnimationFrame: clearTimeout,
    });
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    const actions = createSelectionActions(ports.selection, () => ({
      key: "revision:0:4", anchor: {left: 1, top: 2, bottom: 3},
    }));
    const state = EditorState.create({doc: "text", selection: {anchor: 0, head: 4}});
    const scrollDOM = Object.assign(new EventTarget(), {
      scrollTop: 40, scrollHeight: 200, clientHeight: 100,
      getBoundingClientRect: () => ({top: 0} as DOMRect),
    });
    const editor = {state, scrollDOM, documentTop: 0,
      lineBlockAtHeight: () => ({from: 0, to: 4, top: 0, height: 100}),
    } as unknown as EditorView;
    const post = vi.fn();
    createEditorScrollCoordinator(editor, {
      onScroll: () => actions.dismiss(), post, flushPresentationGeometry() {},
    });
    actions.update();
    const firstEvent = sent.at(-1)!;
    const id = firstEvent.type === "selectionSurface" ? firstEvent.surface.id : 0;
    scrollDOM.dispatchEvent(new Event("scroll"));
    expect(sent.at(-1)).toEqual({type: "dismissSurface", kind: "selection", id});
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(id, "choose", 0)).toBe(false);
    expect(post).not.toHaveBeenCalled();
    vi.advanceTimersByTime(16);
    expect(post).toHaveBeenCalledExactlyOnceWith(expect.objectContaining({fallbackFraction: 0.4}));
    scrollDOM.dispatchEvent(new Event("scroll"));
    vi.advanceTimersByTime(15);
    expect(post).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1);
    // A repeated native scroll event with the same source anchor is a no-op.
    expect(post).toHaveBeenCalledTimes(1);
    expect(editor.state).toBe(state);
    actions.update();
    expect(sent.at(-1)!.type).toBe("dismissSurface");
  });
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

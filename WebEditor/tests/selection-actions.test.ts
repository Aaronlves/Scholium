import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingPorts, type NativeFloatingEvent} from "../native-floating";
import {createSelectionActions, type SelectionActionTarget} from "../selection-actions";
import {projectedSelectionActionRange} from "../live-selection";
import {EditorState} from "@codemirror/state";
import type {EditorView} from "@codemirror/view";
import {createEditorScrollCoordinator} from "../scroll-coordinator";
import {exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {scholiumNoteLanguage} from "../language";
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
describe("source selection action", () => {
  it("an explicit native command reopens an unchanged passage after Escape without reviving stale controls", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const order: string[] = [];
    const ports = createNativeFloatingPorts(event => { sent.push(event); order.push(event.type); });
    let target: SelectionActionTarget | null = {key: "revision:4:12", anchor: {left: 4, top: 8, bottom: 24}, utf16Count: 8};
    const actions = createSelectionActions(ports.selection, () => target, () => target?.key ?? null);
    actions.update();
    const first = sent.at(-1)!;
    if (first.type !== "selectionSurface") throw new Error("Missing initial selection surface");
    expect(actions.dismissForKey({key: "Escape", isComposing: false})).toBe(true);
    const afterEscape = sent.length;
    actions.update();
    expect(sent).toHaveLength(afterEscape);
    order.length = 0;
    expect(actions.presentCurrent()).toBe(true);
    const reopened = sent.at(-1)!;
    order.push("command completed");
    expect(order).toEqual(["selectionSurface", "command completed"]);
    if (reopened.type !== "selectionSurface") throw new Error("Missing reopened selection surface");
    const event = (window as Window & {scholiumNativeFloatingEvent?: Function}).scholiumNativeFloatingEvent!;
    expect(event(first.surface.id, "choose", 0)).toBe(false);
    expect(event(reopened.surface.id, "choose", 0)).toBe(true);
    target = null;
    expect(actions.presentCurrent()).toBe(false);
    expect(event(reopened.surface.id, "choose", 0)).toBe(false);
  });
  it("validates source identity independently of presentation geometry", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    let key: string | null = "revision:4:12";
    let target: SelectionActionTarget | null = {key, anchor: {left: 4, top: 8, bottom: 24}, utf16Count: 8};
    const actions = createSelectionActions(ports.selection, () => target, () => key);
    actions.presentCurrent();
    const shown = sent.at(-1)!;
    if (shown.type !== "selectionSurface") throw new Error("Missing selection surface");
    const event = (window as Window & {scholiumNativeFloatingEvent?: Function}).scholiumNativeFloatingEvent!;
    target = null;
    expect(event(shown.surface.id, "choose", 0)).toBe(true);
    key = "revision:8:16";
    expect(event(shown.surface.id, "choose", 0)).toBe(false);
    key = null;
    expect(event(shown.surface.id, "choose", 0)).toBe(false);
  });
  it("cancels a pending explicit presentation even when no toolbar has been shown", async () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    const target = {key: "revision:4:12", anchor: {left: 4, top: 8, bottom: 24}, utf16Count: 8};
    const actions = createSelectionActions(ports.selection, () => target, () => target.key);
    const revision = actions.presentationRevision;
    let continuePresentation!: () => void;
    const frame = new Promise<void>(resolve => { continuePresentation = resolve; });
    const command = (async () => {
      await frame;
      return actions.presentationRevision === revision && actions.presentCurrent();
    })();
    expect(actions.dismissForKey({key: "Escape", isComposing: false})).toBe(false);
    expect(actions.presentationRevision).toBeGreaterThan(revision);
    continuePresentation();
    expect(await command).toBe(false);
    expect(sent).toEqual([]);
    // A later, independently requested command may reopen the same passage.
    expect(actions.presentCurrent()).toBe(true);
  });
  it("retains an Escape dismissal across offscreen geometry until the exact selection is cleared", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    let key: string | null = "revision:4:12";
    const passage = {key, anchor: {left: 4, top: 8, bottom: 24}, utf16Count: 8};
    let target: SelectionActionTarget | null = passage;
    const actions = createSelectionActions(ports.selection, () => target, () => key);
    actions.update();
    actions.dismissForKey({key: "Escape", isComposing: false});
    const dismissedCount = sent.length;
    target = null;
    actions.update();
    target = passage;
    actions.update();
    expect(sent).toHaveLength(dismissedCount);
    expect(actions.surfaceID).toBeNull();
    key = null;
    target = null;
    actions.update();
    key = passage.key;
    target = passage;
    actions.update();
    expect(sent.at(-1)?.type).toBe("selectionSurface");
  });
  it("distinguishes programmatic scroll dismissal from user cancellation", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    const target = {key: "revision:4:12", anchor: {left: 4, top: 8, bottom: 24}, utf16Count: 8};
    const actions = createSelectionActions(ports.selection, () => target, () => target.key);
    actions.update();
    const revision = actions.presentationRevision;
    expect(actions.dismissForScroll()).toBe(true);
    expect(actions.presentationRevision).toBe(revision);
    expect(actions.surfaceID).toBeNull();
    const dismissedCount = sent.length;
    actions.update();
    expect(sent).toHaveLength(dismissedCount);
    expect(actions.presentCurrent()).toBe(true);
    expect(actions.presentationRevision).toBe(revision);
    expect(actions.dismiss()).toBe(true);
    expect(actions.presentationRevision).toBeGreaterThan(revision);
    const cancelledRevision = actions.presentationRevision;
    expect(actions.dismiss()).toBe(false);
    expect(actions.presentationRevision).toBeGreaterThan(cancelledRevision);
  });
  it.each(["\n", "\r\n"])("offers body selections but never YAML or a cross-boundary selection (%j)", ending => {
    const source = "\uFEFF---" + ending + "tags: [research]" + ending + "---" + ending + "Body 😀.";
    const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    let state = EditorState.create({doc: normalizedDocumentText(source),
      extensions: [scholiumNoteLanguage, controller.extension, exactSourceState]});
    state = state.update({effects: setExactSource.of(source)}).state;
    const body = state.doc.toString().indexOf("Body");
    const project = (from: number, to: number) => {
      const selected = state.update({selection: {anchor: from, head: to}}).state;
      return projectedSelectionActionRange(selected, controller.index(selected));
    };
    expect(project(5, body - 1)).toBeNull();
    expect(project(body - 1, body + 4)).toBeNull();
    expect(project(body, state.doc.length)).toEqual({from: body, to: state.doc.length, utf16Count: "Body 😀.".length});
    const unclosed = EditorState.create({doc: "---\ntags: [research]\nBody text",
      selection: {anchor: 22, head: 26}, extensions: [scholiumNoteLanguage, controller.extension, exactSourceState]});
    expect(projectedSelectionActionRange(unclosed, controller.index(unclosed))).toBeNull();
  });
  it("reports exact CRLF selection length to native availability and excludes an oversized exact range", () => {
    const source = "x\r\n".repeat(10_667);
    let state = EditorState.create({doc: normalizedDocumentText(source),
      selection: {anchor: 0, head: 8_000}, extensions: [exactSourceState]});
    state = state.update({effects: setExactSource.of(source)}).state;
    const body = {frontmatterRange: null, hasUnclosedFrontmatter: false};
    expect(projectedSelectionActionRange(state, body)?.utf16Count).toBe(12_000);
    const selected = state.update({selection: {anchor: 0, head: state.doc.length}}).state;
    expect(projectedSelectionActionRange(selected, body)).toBeNull();
  });
  it("keeps the exact native selection surface for Tab but dismisses ordinary input and composition", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    const target = {key: "revision:1:2", anchor: {left: 1, top: 2, bottom: 3}, utf16Count: 1};
    const actions = createSelectionActions(ports.selection, () => target, () => target?.key ?? null);
    actions.update();
    const revision = actions.presentationRevision;
    expect(actions.dismissForKey({key: "Tab", isComposing: false})).toBe(false);
    expect(actions.presentationRevision).toBeGreaterThan(revision);
    const shown = sent.at(-1)!;
    expect(shown.type).toBe("selectionSurface");
    if (shown.type !== "selectionSurface") throw new Error("Missing selection surface");
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(shown.surface.id, "choose", 0)).toBe(true);
    expect(actions.dismissForKey({key: "a", isComposing: false})).toBe(true);
    actions.update(null);
    actions.update();
    expect(actions.surfaceID).toBeNull();
    actions.presentCurrent();
    expect(actions.dismissForKey({key: "Tab", isComposing: true})).toBe(true);
  });
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
      key: "revision:0:4", anchor: {left: 1, top: 2, bottom: 3}, utf16Count: 4,
    }), () => "revision:0:4");
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
      onScroll: () => actions.dismissForScroll(), onViewportInput: () => actions.dismiss(),
      post, flushPresentationGeometry() {},
    });
    actions.update();
    const revision = actions.presentationRevision;
    const firstEvent = sent.at(-1)!;
    const id = firstEvent.type === "selectionSurface" ? firstEvent.surface.id : 0;
    scrollDOM.dispatchEvent(new Event("scroll"));
    expect(actions.presentationRevision).toBe(revision);
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
    scrollDOM.dispatchEvent(new Event("wheel"));
    expect(actions.presentationRevision).toBeGreaterThan(revision);
  });
  it("rejects an old selection and retains dismissal until selection changes", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    let target: SelectionActionTarget | null = {key: "revision:1:2", anchor: {left: 1, top: 2, bottom: 3}, utf16Count: 1};
    const actions = createSelectionActions(ports.selection, () => target, () => target?.key ?? null);
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
    target = {key: "revision:4:5", anchor: {left: 1, top: 2, bottom: 3}, utf16Count: 1};
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

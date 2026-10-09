import {EditorSelection, EditorState, type Extension, type TransactionSpec} from "@codemirror/state";
import type {EditorView, ViewUpdate} from "@codemirror/view";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createLiveSelectionController} from "../live-selection";

function eventHub() {
  const listeners = new Map<string, Set<() => void>>();
  return {
    addEventListener(type: string, listener: () => void) {
      let entries = listeners.get(type);
      if (!entries) listeners.set(type, entries = new Set());
      entries.add(listener);
    },
    removeEventListener(type: string, listener: () => void) { listeners.get(type)?.delete(listener); },
    emit(type: string) { for (const listener of [...listeners.get(type) ?? []]) listener(); },
  };
}

function pointerHarness() {
  const windowEvents = eventHub();
  vi.stubGlobal("window", windowEvents);
  const completeSelection = vi.fn((state: EditorState) => EditorSelection.single(0, state.doc.length));
  const handleModifiedLink = vi.fn(() => false);
  const handleProjectedPointerStart = vi.fn(() => false);
  const controller = createLiveSelectionController({completeSelection, handleModifiedLink, handleProjectedPointerStart});
  let state = EditorState.create({doc: "# Heading\nBody", extensions: [controller.extension]});
  let plugin: {mousedown(event: MouseEvent): boolean; update?(update: ViewUpdate): void; destroy(): void};
  const dispatch = vi.fn((spec: TransactionSpec) => {
    const transaction = state.update(spec);
    state = transaction.state;
    plugin?.update?.({docChanged: transaction.docChanged} as ViewUpdate);
  });
  const view = {get state() {return state;}, composing: false, compositionStarted: false,
    contentDOM: {ownerDocument: eventHub()}, dispatch} as unknown as EditorView;
  const definition = (controller.extension as Extension[])[1] as unknown as {
    create(view: EditorView): typeof plugin;
  };
  plugin = definition.create(view);
  return {controller, view, dispatch, plugin, completeSelection, handleModifiedLink, handleProjectedPointerStart,
    press() {return plugin.mousedown({button: 0, detail: 1} as MouseEvent);},
    release() {windowEvents.emit("mouseup");},
    startComposition() {Object.defineProperty(view, "compositionStarted", {value: true});},
  };
}

afterEach(() => vi.unstubAllGlobals());

describe("Live Preview pointer selection lifetime", () => {
  it("keeps drag projection stable until the final pointer selection is committed", async () => {
    const h = pointerHarness();
    h.press();
    h.dispatch({selection: {anchor: 2, head: 9}, userEvent: "select.pointer"});
    expect(h.controller.selection(h.view.state).main).toMatchObject({anchor: 0, head: 0});
    h.release();
    await Promise.resolve();
    expect(h.completeSelection).toHaveBeenCalledOnce();
    expect(h.controller.selection(h.view.state).eq(h.view.state.selection)).toBe(true);
    h.plugin.destroy();
  });

  it("does not complete an old pointer selection after source input supersedes queued mouse-up", async () => {
    const h = pointerHarness();
    h.press();
    h.dispatch({selection: {anchor: 2, head: 9}, userEvent: "select.pointer"});
    h.release();
    h.dispatch({changes: {from: 2, to: 9, insert: "New"}, selection: {anchor: 5}, userEvent: "input.type"});
    const expected = h.view.state;
    await Promise.resolve();
    expect(h.completeSelection).not.toHaveBeenCalled();
    expect(h.view.state).toBe(expected);
    expect(h.controller.selection(h.view.state).eq(h.view.state.selection)).toBe(true);
    h.plugin.destroy();
  });

  it("yields pointer entry to composition before the first marked-text change", () => {
    const h = pointerHarness();
    h.startComposition();
    expect(h.press()).toBe(false);
    expect(h.handleModifiedLink).not.toHaveBeenCalled();
    expect(h.handleProjectedPointerStart).not.toHaveBeenCalled();
    expect(h.dispatch).not.toHaveBeenCalled();
    h.plugin.destroy();
  });

  it("does not expand a completed pointer selection after composition starts", async () => {
    const h = pointerHarness();
    h.press();
    h.dispatch({selection: {anchor: 2, head: 9}, userEvent: "select.pointer"});
    h.release();
    h.startComposition();
    const expected = h.view.state.selection;
    await Promise.resolve();
    expect(h.completeSelection).not.toHaveBeenCalled();
    expect(h.view.state.selection.eq(expected, true)).toBe(true);
    h.plugin.destroy();
  });
});

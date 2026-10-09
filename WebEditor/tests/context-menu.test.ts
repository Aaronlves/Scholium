import {EditorSelection, EditorState} from "@codemirror/state";
import type {EditorView} from "@codemirror/view";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createEditorContextMenuExtension, selectionForContextClick} from "../context-menu";
import type {EditorContext, EditorMode} from "../protocol";

describe("editor context-menu selection", () => {
  it("preserves a passage when secondary click lands inside it", () => {
    const selected = EditorSelection.single(4, 12);
    expect(selectionForContextClick(selected, 8).eq(selected)).toBe(true);
  });

  it("moves the authoritative caret before evaluating an outside click", () => {
    const selected = EditorSelection.single(4, 12);
    const result = selectionForContextClick(selected, 18);
    expect(result.main.anchor).toBe(18);
    expect(result.main.head).toBe(18);
  });

  it("keeps an empty selection at the clicked insertion point", () => {
    const result = selectionForContextClick(EditorSelection.single(6), 8);
    expect(result.main.empty).toBe(true);
    expect(result.main.head).toBe(8);
  });

  it("treats the exclusive selection end as outside the selected passage", () => {
    const selected = EditorSelection.single(4, 12);
    expect(selectionForContextClick(selected, 12).main.empty).toBe(true);
  });

  it("preserves multiple ranges when the click belongs to any one of them", () => {
    const selected = EditorSelection.create([
      EditorSelection.range(2, 5),
      EditorSelection.range(10, 14),
    ], 1);
    expect(selectionForContextClick(selected, 11).eq(selected)).toBe(true);
  });
});

describe("keyboard editor context menus", () => {
  afterEach(() => vi.unstubAllGlobals());

  function fixture(mode: EditorMode = "source") {
    const {document, window} = parseHTML("<html><body><div><input data-scholium-title-input><main></main></div></body></html>");
    vi.stubGlobal("Element", window.Element);
    const dom = document.querySelector("div")!;
    const content = dom.querySelector("main")!;
    const selection = EditorSelection.create([
      EditorSelection.range(1, 4), EditorSelection.range(14, 8),
    ], 1);
    const state = EditorState.create({doc: "Lead 中文 é body text", selection,
      extensions: EditorState.allowMultipleSelections.of(true)});
    const composition = {active: false};
    const context = (): EditorContext => ({
      selections: state.selection.ranges.map(({anchor, head}) => ({anchor, head})),
      activeInlineConstructs: [], activeBlockConstructs: [], composing: composition.active,
      availableCommands: ["bold"],
    });
    const request = vi.fn();
    const view = {state, dom, compositionStarted: false, composing: false,
      dispatch: vi.fn(), focus: vi.fn(), posAtCoords: vi.fn(),
      coordsAtPos: vi.fn(() => ({left: 41, right: 42, top: 70, bottom: 89}))};
    const definition = createEditorContextMenuExtension({context, mode: () => mode, request}) as unknown as {
      create(view: EditorView): {destroy(): void};
    };
    const plugin = definition.create(view as unknown as EditorView);
    function press(fields: Partial<KeyboardEvent>, target: Element = content, prevented = false) {
      const event = new window.Event("keydown", {bubbles: true, cancelable: true});
      Object.assign(event, {key: "", keyCode: 0, ctrlKey: false, metaKey: false,
        altKey: false, shiftKey: false, isComposing: false, repeat: false}, fields);
      if (prevented) event.preventDefault();
      target.dispatchEvent(event);
      return event;
    }
    return {view, state, composition, request, press, plugin, dom};
  }

  it.each(["ContextMenu", "F10"])("opens %s at the active source selection without pointer remapping", key => {
    const h = fixture();
    const event = h.press({key, shiftKey: key === "F10"});
    expect(event.defaultPrevented).toBe(true);
    expect(h.request).toHaveBeenCalledExactlyOnceWith({clientX: 41, clientY: 89, mode: "source", context: {
      selections: [{anchor: 1, head: 4}, {anchor: 14, head: 8}],
      activeInlineConstructs: [], activeBlockConstructs: [], composing: false, availableCommands: ["bold"],
    }});
    expect(h.view.coordsAtPos).toHaveBeenCalledExactlyOnceWith(8);
    expect(h.view.focus).toHaveBeenCalledOnce();
    expect(h.view.posAtCoords).not.toHaveBeenCalled();
    expect(h.view.dispatch).not.toHaveBeenCalled();
    expect(h.state.selection.main.anchor).toBe(14);
    h.plugin.destroy();
  });

  it.each([
    {key: "F10"}, {key: "Enter", shiftKey: true},
    {key: "F10", shiftKey: true, metaKey: true},
    {key: "F10", shiftKey: true, altKey: true},
    {key: "F10", shiftKey: true, ctrlKey: true},
    {key: "ContextMenu", metaKey: true}, {key: "ContextMenu", altKey: true},
    {key: "ContextMenu", ctrlKey: true},
    {key: "ContextMenu", isComposing: true}, {key: "ContextMenu", keyCode: 229},
  ])("does not steal an unrelated or composition keystroke: %j", fields => {
    const h = fixture();
    expect(h.press(fields).defaultPrevented).toBe(false);
    expect(h.request).not.toHaveBeenCalled();
    expect(h.view.focus).not.toHaveBeenCalled();
    expect(h.view.dispatch).not.toHaveBeenCalled();
    h.plugin.destroy();
  });

  it.each(["context", "compositionStarted", "composing"])("leaves the menu to the input method during %s", source => {
    const h = fixture();
    if (source === "context") h.composition.active = true;
    else h.view[source as "compositionStarted" | "composing"] = true;
    expect(h.press({key: "ContextMenu"}).defaultPrevented).toBe(false);
    expect(h.request).not.toHaveBeenCalled();
    expect(h.view.focus).not.toHaveBeenCalled();
    h.plugin.destroy();
  });

  it("keeps title input native, ignores key repetition, and removes its listener on destruction", () => {
    const h = fixture("livePreview");
    expect(h.press({key: "ContextMenu"}, h.dom.querySelector("input")!).defaultPrevented).toBe(false);
    expect(h.request).not.toHaveBeenCalled();
    h.press({key: "ContextMenu"});
    h.press({key: "ContextMenu", repeat: true});
    expect(h.request).toHaveBeenCalledOnce();
    h.plugin.destroy();
    h.press({key: "ContextMenu"});
    expect(h.request).toHaveBeenCalledOnce();
  });

  it("does not duplicate a keyboard event already handled by another owner", () => {
    const h = fixture();
    h.press({key: "ContextMenu"}, h.dom, true);
    expect(h.request).not.toHaveBeenCalled();
    expect(h.view.focus).not.toHaveBeenCalled();
    h.plugin.destroy();
  });
});

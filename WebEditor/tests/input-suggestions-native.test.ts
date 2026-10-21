import {closeCompletion, completionStatus, currentCompletions, startCompletion, setSelectedCompletion} from "@codemirror/autocomplete";
import {EditorState, StateEffect, Transaction, type Extension, type TransactionSpec} from "@codemirror/state";
import {EditorView, type ViewUpdate} from "@codemirror/view";
import {history, undoDepth} from "@codemirror/commands";
import {describe, expect, it, vi} from "vitest";
import {createEditorInputSuggestions} from "../input-suggestions";
import type {EditorMode} from "../protocol";
import type {NativeSuggestionPort} from "../native-floating";

type Plugin = {update(update: ViewUpdate): void; refresh(): void; destroy(): void};
type Measure = NonNullable<Parameters<EditorView["requestMeasure"]>[0]>;

// Real CodeMirror completion state/query scheduling, with only native presentation
// and geometry substituted. This does not establish WK focus/IME acceptance.
function harness(source = "/", setup: {mode?: EditorMode; focused?: boolean; documentFocused?: boolean; composing?: boolean; extensions?: Extension[]} = {}) {
  let mode = setup.mode ?? "livePreview", composing = setup.composing ?? false;
  let focused = setup.focused ?? true;
  const requests: string[] = [], measures: Measure[] = [];
  const shown: Array<{surface: Parameters<NativeSuggestionPort["show"]>[0]; callbacks: Parameters<NativeSuggestionPort["show"]>[1]}> = [];
  const port: NativeSuggestionPort = {show: vi.fn((surface, callbacks) => {shown.push({surface, callbacks}); return shown.length;}), hide: vi.fn()};
  const suggestions = createEditorInputSuggestions({nativeFloating: port, mode: () => mode,
    dialect: () => null, isComposing: () => composing, protectedRanges: () => [],
    requestLinkCompletions: id => requests.push(id), didApply() {}});
  let state = EditorState.create({doc: source, selection: {anchor: source.length},
    extensions: [history(), suggestions.extension, ...setup.extensions ?? []]});
  let native: Plugin | undefined, completion: {update(update: ViewUpdate): void} | undefined;
  const contentDOM = {};
  const root = {get activeElement() { return focused ? contentDOM : null; }};
  let anchor = {left: 10, top: 20, bottom: 40};
  const coords = vi.fn(() => anchor);
  const view = {get state() {return state;}, composing: false,
    get hasFocus() {return focused && setup.documentFocused !== false;}, contentDOM, root,
    requestMeasure(request: Measure) { measures.push(request); }, coordsAtPos: coords,
    dispatch(spec: TransactionSpec) {
      const startState = state, transaction = state.update(spec);
      state = transaction.state;
      const update = {view, state, startState, transactions: [transaction],
        docChanged: transaction.docChanged, selectionSet: !!transaction.selection} as unknown as ViewUpdate;
      completion?.update(update);
      native?.update(update);
    },
  } as unknown as EditorView;
  const extensions = suggestions.extension as Extension[];
  const definition = extensions[3] as unknown as {create(view: EditorView): Plugin; domEventHandlers: {focus(): void; blur(): void; compositionstart(): void}};
  native = definition.create(view);
  const completionDefinition = (extensions[0] as Extension[])[3] as unknown as {create(view: EditorView): {update(update: ViewUpdate): void}};
  completion = completionDefinition.create(view);
  return {view, port, coords, shown, measures, requests, suggestions, definition, native, state: () => state,
    setMode(value: EditorMode) {mode = value;}, setComposing(value: boolean) {composing = value;},
    setFocus(value: boolean) {focused = value;}, setAnchor(value: typeof anchor) {anchor = value;},
    flush() {for (const request of measures.splice(0)) request.write?.(request.read(view), view);},
    destroy() {closeCompletion(view); suggestions.resetDocument(); native!.destroy();},
  };
}

describe("Native completion geometry admission", () => {
  async function run(body: (timer: ReturnType<typeof vi.spyOn>) => Promise<void> | void) {
    vi.useFakeTimers();
    vi.stubGlobal("window", {setTimeout, clearTimeout});
    const timer = vi.spyOn(window, "setTimeout");
    try {await body(timer);} finally {vi.unstubAllGlobals(); vi.useRealTimers();}
  }

  it.each([
    {}, {mode: "source" as const}, {mode: "review" as const}, {focused: false}, {composing: true},
    {extensions: [EditorState.readOnly.of(true)]}, {extensions: [EditorView.editable.of(false)]},
  ])("does no native geometry work without a displayable list (%j)", async setup => run(async timer => {
    const h = harness("Ordinary source", setup);
    try {
      for (let index = 0; index < 10; index++) h.native.update({docChanged: false, selectionSet: false,
        viewportChanged: true, geometryChanged: true} as ViewUpdate);
      await vi.advanceTimersByTimeAsync(100);
      expect(h.measures).toHaveLength(0);
      expect(h.coords).not.toHaveBeenCalled();
      expect(timer).not.toHaveBeenCalled();
      expect(h.port.show).not.toHaveBeenCalled();
    } finally {h.destroy();}
  }));

  it.each([true, false])("waits for candidates, retains pending ownership, and yields stale geometry on scroll (empty result %s)", async empty => run(async timer => {
    const h = harness("[[F");
    try {
      startCompletion(h.view);
      await vi.advanceTimersByTimeAsync(50);
      expect(completionStatus(h.state())).toBe("pending");
      expect(h.requests).toHaveLength(1);
      expect(h.measures).toHaveLength(0);
      expect(timer).not.toHaveBeenCalled();
      h.suggestions.resolveLinkCompletionQuery(h.requests[0], [{label: "First", insertion: "First", detail: "", availability: "available"}]);
      await vi.advanceTimersByTimeAsync(0);
      h.flush();
      expect(h.shown).toHaveLength(1);
      const old = h.shown[0].callbacks;
      const timerCount = timer.mock.calls.length;
      h.view.dispatch({changes: {from: h.state().doc.length, insert: "o"}, selection: {anchor: 4},
        annotations: Transaction.userEvent.of("input.type")});
      expect(completionStatus(h.state())).toBe("pending");
      expect(currentCompletions(h.state())).toEqual([]);
      expect(h.measures).toHaveLength(0);
      expect(timer).toHaveBeenCalledTimes(timerCount);
      expect(h.port.hide).not.toHaveBeenCalled();
      expect(old.choose?.(0)).toBe(false);
      // CodeMirror also reports viewportChanged when typing only maps the
      // viewport's document bounds. That is not a scroll and must retain the
      // native list through its pending query, without reading geometry.
      h.native.update({docChanged: true, selectionSet: true,
        viewportChanged: true, viewportMoved: false} as ViewUpdate);
      expect(h.port.hide).not.toHaveBeenCalled();
      expect(h.measures).toHaveLength(0);
      expect(timer).toHaveBeenCalledTimes(timerCount);
      expect(h.coords).toHaveBeenCalledTimes(1);
      h.setAnchor({left: 25, top: 100, bottom: 120});
      h.native.update({docChanged: false, selectionSet: false,
        viewportChanged: true, viewportMoved: true} as ViewUpdate);
      expect(h.port.hide).toHaveBeenCalledWith(1);
      expect(h.measures).toHaveLength(0);
      expect(timer).toHaveBeenCalledTimes(timerCount);
      expect(h.coords).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(100);
      expect(h.requests).toHaveLength(2);
      h.suggestions.resolveLinkCompletionQuery(h.requests[1], empty ? []
        : [{label: "Follow", insertion: "Follow", detail: "", availability: "available"}]);
      await vi.advanceTimersByTimeAsync(0);
      h.flush();
      expect(h.port.hide).toHaveBeenCalledWith(1);
      expect(h.coords).toHaveBeenCalledTimes(empty ? 1 : 2);
      expect(h.shown).toHaveLength(empty ? 1 : 2);
      if (!empty) expect(h.shown[1].surface.top).toBe(100);
    } finally {h.destroy();}
  }));

  it("resumes ready candidates on DOM focus when WK window activation has not reported document focus", async () => run(async timer => {
    const h = harness("/", {focused: false, documentFocused: false});
    try {
      startCompletion(h.view);
      await vi.advanceTimersByTimeAsync(100);
      expect(currentCompletions(h.state()).length).toBeGreaterThan(0);
      expect(h.view.hasFocus).toBe(false);
      expect(h.measures).toHaveLength(0);
      expect(timer).not.toHaveBeenCalled();
      expect(h.coords).not.toHaveBeenCalled();
      h.setFocus(true);
      // CodeMirror's global hasFocus remains false, so its focus-change update
      // need not fire. The content DOM event still identifies the input owner.
      h.definition.domEventHandlers.focus.call(h.native);
      expect(h.view.hasFocus).toBe(false);
      h.flush();
      expect(h.shown).toHaveLength(1);
      expect(h.coords).toHaveBeenCalledTimes(1);
      const previous = h.shown[0].callbacks;
      h.setFocus(false);
      h.definition.domEventHandlers.blur.call(h.native);
      expect(h.port.hide).toHaveBeenCalledWith(1);
      expect(previous.choose?.(0)).toBe(false);
      const timers = timer.mock.calls.length;
      await vi.advanceTimersByTimeAsync(100);
      expect(h.coords).toHaveBeenCalledTimes(1);
      expect(timer).toHaveBeenCalledTimes(timers);
      expect(h.state().doc.toString()).toBe("/");
      expect(undoDepth(h.state())).toBe(0);
    } finally {h.destroy();}
  }));

  it.each(["composition", "readOnly", "noneditable", "sourceMode", "blur"])("rejects stale reads and actions immediately after %s", async reason => run(async () => {
    const h = harness();
    try {
      startCompletion(h.view);
      await vi.advanceTimersByTimeAsync(50);
      h.flush();
      expect(h.shown).toHaveLength(1);
      const actions = h.shown[0].callbacks;
      h.native.refresh();
      const queued = h.measures.splice(0);
      if (reason === "composition") {h.setComposing(true); h.definition.domEventHandlers.compositionstart.call(h.native);}
      else if (reason === "sourceMode") h.setMode("source");
      else if (reason === "blur") {h.setFocus(false); h.definition.domEventHandlers.blur.call(h.native);}
      else h.view.dispatch({effects: StateEffect.appendConfig.of(reason === "readOnly"
        ? EditorState.readOnly.of(true) : EditorView.editable.of(false))});
      h.native.refresh();
      const reads = h.coords.mock.calls.length;
      for (const request of queued) request.write?.(request.read(h.view), h.view);
      await vi.advanceTimersByTimeAsync(60);
      expect(h.coords).toHaveBeenCalledTimes(reads);
      expect(actions.choose?.(0)).toBe(false);
      actions.select?.(1);
      expect(h.state().doc.toString()).toBe("/");
      expect(undoDepth(h.state())).toBe(0);
      expect(h.port.hide).toHaveBeenCalledWith(1);
      expect(h.shown).toHaveLength(1);
    } finally {h.destroy();}
  }));

  it("uses one WK idle fallback, ignores the stalled measure, and tracks later viewport geometry", async () => run(async () => {
    const h = harness();
    try {
      startCompletion(h.view);
      await vi.advanceTimersByTimeAsync(100);
      expect(h.shown).toHaveLength(1);
      expect(h.coords).toHaveBeenCalledTimes(1);
      h.flush();
      expect(h.coords).toHaveBeenCalledTimes(1);
      h.setAnchor({left: 25, top: 100, bottom: 120});
      h.native.update({docChanged: false, selectionSet: false, viewportChanged: true, geometryChanged: true} as ViewUpdate);
      h.flush();
      expect(h.shown.at(-1)?.surface.top).toBe(100);
      expect(h.shown).toHaveLength(2);
      h.view.dispatch({effects: setSelectedCompletion(1)});
      h.flush();
      expect(h.shown.at(-1)?.surface.selected).toBe(1);
      expect(h.state().doc.toString()).toBe("/");
      expect(undoDepth(h.state())).toBe(0);
      closeCompletion(h.view);
      const reads = h.coords.mock.calls.length;
      await vi.advanceTimersByTimeAsync(60);
      h.flush();
      expect(h.coords).toHaveBeenCalledTimes(reads);
      expect(h.port.hide).toHaveBeenCalledWith(h.shown.length);
    } finally {h.destroy();}
  }));
});

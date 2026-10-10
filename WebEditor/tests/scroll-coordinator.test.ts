import {EditorState} from "@codemirror/state";
import {EditorView} from "@codemirror/view";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createEditorScrollCoordinator, documentToolbarScrollMargin} from "../scroll-coordinator";

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

function anchorRestorationHarness(fontsReady: Promise<void>) {
  vi.stubGlobal("window", {
    setTimeout, clearTimeout,
    requestAnimationFrame: (callback: () => void) => setTimeout(callback, 16),
    cancelAnimationFrame: clearTimeout,
  });
  vi.stubGlobal("document", {fonts: {ready: fontsReady}});
  const listeners = new Map<string, () => void>();
  const scrollDOM = {
    scrollTop: 0, scrollHeight: 2_000, clientHeight: 100,
    getBoundingClientRect: () => ({top: 0}),
    addEventListener: (event: string, callback: () => void) => { listeners.set(event, callback); },
  };
  let blockTop = 300;
  const editor = {
    state: EditorState.create({doc: "x".repeat(2_000)}), scrollDOM,
    get documentTop() { return -scrollDOM.scrollTop; },
    lineBlockAtHeight: (height: number) => ({from: height, to: height + 1, top: height, height: 20}),
    lineBlockAt: () => ({from: 300, to: 320, top: blockTop, height: 20}),
    requestMeasure: (request: {read(): number; write(value: number): void}) => request.write(request.read()),
    dispatch: () => {},
  } as unknown as EditorView;
  const coordinator = createEditorScrollCoordinator(editor, {
      onViewportInput() {},
    onScroll: () => {}, post: () => {}, flushPresentationGeometry: () => {},
  });
  return {
    scrollDOM,
    emit: (event: string) => listeners.get(event)?.(),
    setBlockTop: (top: number) => { blockTop = top; },
    restore: () => coordinator.setAnchor({
      sourceUTF16Offset: 300, blockUTF16LowerBound: 300, blockUTF16UpperBound: 320,
      relativeBlockPosition: 0, fallbackFraction: 0.2,
    }),
  };
}

describe("scroll coordination across runtime reuse", () => {
  it("a completed explicit reveal survives its own scroll receipt but yields to user input and changed geometry", () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {
      setTimeout, clearTimeout,
      requestAnimationFrame: (callback: () => void) => setTimeout(callback, 16),
      cancelAnimationFrame: clearTimeout,
    });
    const scrollDOM = Object.assign(new EventTarget(), {
      scrollTop: 0, scrollLeft: 0, scrollHeight: 2_000, clientHeight: 100,
      getBoundingClientRect: () => ({top: 0}),
    });
    const state = EditorState.create({doc: "x".repeat(2_000), selection: {anchor: 20, head: 1_800}});
    const editor = {state, scrollDOM, documentTop: 0,
      dispatch: vi.fn(),
      coordsAtPos: vi.fn(() => { scrollDOM.scrollTop = 1_700; scrollDOM.scrollLeft = 25; return null; }),
      lineBlockAtHeight: () => ({from: 1_700, to: 1_800, top: 1_700, height: 100}),
    } as unknown as EditorView;
    const dismiss = vi.fn();
    const input = vi.fn();
    const coordinator = createEditorScrollCoordinator(editor, {
      onScroll: dismiss, onViewportInput: input, post() {}, flushPresentationGeometry() {},
    });
    coordinator.revealPosition(state.selection.main.head);
    expect(editor.coordsAtPos).toHaveBeenCalledExactlyOnceWith(1_800);
    scrollDOM.dispatchEvent(new Event("scroll"));
    scrollDOM.dispatchEvent(new Event("scroll"));
    expect(dismiss).not.toHaveBeenCalled();
    expect(editor.state).toBe(state);
    scrollDOM.scrollLeft += 1;
    scrollDOM.dispatchEvent(new Event("scroll"));
    expect(dismiss).toHaveBeenCalledTimes(1);
    coordinator.revealPosition(state.selection.main.head);
    scrollDOM.dispatchEvent(new Event("wheel"));
    expect(input).toHaveBeenCalledOnce();
    scrollDOM.dispatchEvent(new Event("scroll"));
    expect(dismiss).toHaveBeenCalledTimes(2);
    coordinator.revealPosition(state.selection.main.head);
    coordinator.setTop(scrollDOM.scrollTop);
    scrollDOM.dispatchEvent(new Event("scroll"));
    expect(dismiss).toHaveBeenCalledTimes(3);
  });

  it.each(["wheel", "keydown", "pointerdown", "touchstart"])("keeps the researcher viewport after %s input during restoration", async (input) => {
    vi.useFakeTimers();
    let finishFonts!: () => void;
    const harness = anchorRestorationHarness(new Promise<void>(resolve => { finishFonts = resolve; }));
    harness.restore();
    await Promise.resolve();
    expect(harness.scrollDOM.scrollTop).toBe(296);

    harness.emit(input);
    harness.scrollDOM.scrollTop = 700;
    harness.emit("scroll");
    vi.advanceTimersByTime(100);
    finishFonts();
    await Promise.resolve();

    expect(harness.scrollDOM.scrollTop).toBe(700);
  });

  it("finishes font-layout restoration after its own programmatic scroll reports", async () => {
    vi.useFakeTimers();
    let finishFonts!: () => void;
    const harness = anchorRestorationHarness(new Promise<void>(resolve => { finishFonts = resolve; }));
    harness.restore();
    harness.emit("scroll");
    vi.advanceTimersByTime(100);
    expect(harness.scrollDOM.scrollTop).toBe(296);

    harness.setBlockTop(500);
    finishFonts();
    await Promise.resolve();

    expect(harness.scrollDOM.scrollTop).toBe(496);
  });

  it("updates and clears the covered caret region when native toolbar overlap changes", () => {
    let inset = "52px";
    const dom = {};
    vi.stubGlobal("getComputedStyle", (element: unknown) => {
      expect(element).toBe(dom);
      return {getPropertyValue: (property: string) => {
        expect(property).toBe("--scholium-document-toolbar-inset");
        return inset;
      }};
    });
    const state = EditorState.create({doc: "Retained 中文 source", extensions: [documentToolbarScrollMargin]});
    const view = {dom, state, scaleY: 1} as unknown as EditorView;
    const margin = state.facet(EditorView.scrollMargins)[0];
    expect(margin(view)).toEqual({top: 52});
    // Focus Layout changes the native overlap on the retained editor, while
    // scaled editor geometry still uses the same visual coordinate system.
    inset = "28px";
    Object.assign(view, {scaleY: 1.5});
    expect(margin(view)).toEqual({top: 42});
    // Tabs, recovery notices, or a hidden titlebar can eliminate overlap.
    // Ordinary document padding must not become a standing scroll margin.
    for (const absent of ["0px", "", "-1px"]) {
      inset = absent;
      expect(margin(view)).toBeNull();
    }
  });

  it("does not repost an unchanged source anchor", () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {
      setTimeout, clearTimeout,
      requestAnimationFrame: (callback: () => void) => setTimeout(callback, 16),
      cancelAnimationFrame: clearTimeout,
    });
    let scroll = () => {};
    const scrollDOM = {
      scrollTop: 0, scrollHeight: 2_000, clientHeight: 100,
      getBoundingClientRect: () => ({top: 0}),
      addEventListener: (_event: string, callback: () => void) => { scroll = callback; },
    };
    const editor = {
      state: EditorState.create({doc: "x".repeat(2_000)}), scrollDOM,
      documentTop: 0,
      lineBlockAtHeight: () => ({from: 0, to: 1, top: 0, height: 20}),
    } as unknown as EditorView;
    const post = vi.fn();
    createEditorScrollCoordinator(editor, {
      onViewportInput() {},
      onScroll: () => {}, post, flushPresentationGeometry: () => {},
    });

    scroll();
    vi.advanceTimersByTime(16);
    scroll();
    vi.advanceTimersByTime(16);

    expect(post).toHaveBeenCalledOnce();
  });

  it.each([16, 1_000])("reports the latest viewport during uninterrupted scroll with %i ms frames", (frameDelay) => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {
      setTimeout, clearTimeout,
      requestAnimationFrame: (callback: () => void) => setTimeout(callback, frameDelay),
      cancelAnimationFrame: clearTimeout,
    });
    let scroll = () => {};
    const scrollDOM = {
      scrollTop: 0, scrollHeight: 2_000, clientHeight: 100,
      getBoundingClientRect: () => ({top: 0}),
      addEventListener: (_event: string, callback: () => void) => { scroll = callback; },
    };
    const editor = {
      state: EditorState.create({doc: "x".repeat(2_000)}), scrollDOM,
      get documentTop() { return -scrollDOM.scrollTop; },
      lineBlockAtHeight: (height: number) => ({from: height, to: height + 1, top: height, height: 20}),
    } as unknown as EditorView;
    const post = vi.fn();
    createEditorScrollCoordinator(editor, {
      onViewportInput() {},
      onScroll: () => {}, post, flushPresentationGeometry: () => {},
    });
    // Keep the gap below the old 120 ms debounce for the entire gesture.
    for (let index = 1; index <= 100; index += 1) {
      scrollDOM.scrollTop = index * 10;
      scroll();
      vi.advanceTimersByTime(5);
      if (index === 20) expect(post.mock.calls.length).toBeGreaterThan(0);
    }
    expect(post.mock.calls.length).toBeGreaterThan(1);
    expect(post.mock.calls.length).toBeLessThanOrEqual(frameDelay === 16 ? 32 : 10);
    vi.advanceTimersByTime(50);
    expect(post.mock.lastCall?.[0]).toMatchObject({
      sourceUTF16Offset: 1_008, fallbackFraction: 1_000 / 1_900,
    });
    const count = post.mock.calls.length;
    vi.advanceTimersByTime(120);
    expect(post).toHaveBeenCalledTimes(count);
  });

  it("cancels old scroll reports and pending geometry before a new document", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {
      setTimeout, clearTimeout,
      requestAnimationFrame: (callback: () => void) => setTimeout(callback, 16),
      cancelAnimationFrame: clearTimeout,
    });
    let scroll: () => void = () => {};
    const scrollDOM = {
      scrollTop: 75, scrollLeft: 20, scrollHeight: 500, clientHeight: 100,
      getBoundingClientRect: () => ({top: 0}),
      addEventListener: (_event: string, callback: () => void) => { scroll = callback; },
    };
    type Measure = {
      read(view: EditorView): number | null | undefined;
      write?(value: number | null | undefined, view: EditorView): void;
    };
    const measurements: Measure[] = [];
    const editor = {
      state: EditorState.create({doc: "same text"}),
      scrollDOM, documentTop: 0,
      lineBlockAtHeight: () => ({from: 0, to: 9, top: 0, height: 20}),
      lineBlockAt: () => ({from: 0, to: 9, top: 0, height: 20}),
      requestMeasure: (request: Measure) => measurements.push(request),
    } as unknown as EditorView;
    const post = vi.fn();
    const coordinator = createEditorScrollCoordinator(editor, {
      onViewportInput() {},
      onScroll: () => {}, post, flushPresentationGeometry: () => {},
    });
    scroll();
    coordinator.scheduleGeometryReport(coordinator.captureGeometry());
    coordinator.resetDocument();
    await Promise.resolve();
    vi.runAllTimers();
    expect(post).not.toHaveBeenCalled();
    expect(measurements).toHaveLength(0);
    expect(scrollDOM.scrollTop).toBe(0);
    expect(scrollDOM.scrollLeft).toBe(0);

    // An already queued CodeMirror measure must also be invalid after reset,
    // even when successive notes have the same Text object or are both empty.
    coordinator.scheduleGeometryReport(coordinator.captureGeometry());
    await Promise.resolve();
    const pending = measurements.pop()!;
    const measured = pending.read(editor);
    coordinator.resetDocument();
    pending.write!(measured, editor);
    expect(post).not.toHaveBeenCalled();

    coordinator.scheduleGeometryReport();
    await Promise.resolve();
    const current = measurements.pop()!;
    current.write!(current.read(editor), editor);
    expect(post).toHaveBeenCalledOnce();
  });
});

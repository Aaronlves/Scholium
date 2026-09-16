import {EditorState} from "@codemirror/state";
import type {EditorView} from "@codemirror/view";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createEditorScrollCoordinator} from "../scroll-coordinator";

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

describe("scroll coordination across runtime reuse", () => {
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

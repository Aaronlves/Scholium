import type {EditorView} from "@codemirror/view";
import {afterEach, describe, expect, it, vi} from "vitest";
import {awaitMarkdownFontLoading, measureMarkdownEditor} from "../bootstrap";

type MeasurementRequest = NonNullable<Parameters<EditorView["requestMeasure"]>[0]>;

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("opening editor measurement", () => {
  function pausedFrameView() {
    let pending: MeasurementRequest | undefined;
    const view = {
      state: {selection: {main: {head: 7}}},
      requestMeasure: vi.fn((request: MeasurementRequest) => { pending = request; }),
      coordsAtPos: vi.fn(() => {
        const request = pending;
        pending = undefined;
        if (request) {
          // CodeMirror catches throwing reads and omits their write callback.
          try { request.write?.(request.read(view as unknown as EditorView), view as unknown as EditorView); }
          catch { /* CodeMirror's BadMeasure path. */ }
        }
        return null;
      }),
    };
    return view;
  }

  it("flushes a real queued measurement through the public geometry API without waiting for a frame", async () => {
    const view = pausedFrameView();
    const read = vi.fn();
    await measureMarkdownEditor(view as unknown as EditorView, read);
    expect(read).toHaveBeenCalledOnce();
    expect(view.coordsAtPos).toHaveBeenCalledWith(7);
  });

  it("rejects the original read failure even when CodeMirror would swallow it and skip write", async () => {
    const view = pausedFrameView();
    const failure = new Error("invalid opening geometry");
    await expect(measureMarkdownEditor(view as unknown as EditorView, () => { throw failure; })).rejects.toBe(failure);
  });

  it.each(["requestMeasure", "coordsAtPos"] as const)("rejects a failure from %s without leaving a pending preparation", async operation => {
    const view = pausedFrameView();
    const failure = new Error("measurement API failed");
    view[operation].mockImplementation(() => { throw failure; });
    await expect(measureMarkdownEditor(view as unknown as EditorView, () => {})).rejects.toBe(failure);
  });
});

describe("opening font loading task boundary", () => {
  function fontSet(status: FontFaceSetLoadStatus) {
    const readyRead = vi.fn();
    const fonts = {
      status,
      get ready(): Promise<FontFaceSet> {
        readyRead(fonts.status);
        return Promise.resolve(fonts as unknown as FontFaceSet);
      },
    };
    return {fonts, readyRead};
  }

  it("lets a browser task update loading fonts even when the prior ready promise is fulfilled", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {setTimeout});
    const {fonts, readyRead} = fontSet("loading");
    await fonts.ready;
    readyRead.mockClear();
    setTimeout(() => { fonts.status = "loaded"; }, 0);
    const current = vi.fn();
    const measured = vi.fn();
    const pending = awaitMarkdownFontLoading(fonts, current).then(measured);
    await Promise.resolve();
    expect(readyRead).not.toHaveBeenCalled();
    expect(measured).not.toHaveBeenCalled();
    await vi.runAllTimersAsync();
    await pending;
    expect(readyRead).toHaveBeenCalledExactlyOnceWith("loaded");
    expect(measured).toHaveBeenCalledOnce();
    expect(current).toHaveBeenCalledTimes(3);
  });

  it.each(["expired preparation", "detached document"])("admits %s before another font wait or measurement", async message => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {setTimeout});
    const {fonts, readyRead} = fontSet("loading");
    let current = true;
    setTimeout(() => { current = false; }, 0);
    const measured = vi.fn();
    const pending = awaitMarkdownFontLoading(fonts, () => {
      if (!current) throw new Error(message);
    }).then(measured);
    const rejected = expect(pending).rejects.toThrow(message);
    await vi.runAllTimersAsync();
    await rejected;
    expect(readyRead).not.toHaveBeenCalled();
    expect(measured).not.toHaveBeenCalled();
  });

  it("adds no task delay when fonts are already loaded", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {setTimeout});
    const {fonts, readyRead} = fontSet("loaded");
    await awaitMarkdownFontLoading(fonts, () => {});
    expect(readyRead).toHaveBeenCalledExactlyOnceWith("loaded");
    expect(vi.getTimerCount()).toBe(0);
  });
});

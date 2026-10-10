import type {EditorView} from "@codemirror/view";
import {describe, expect, it, vi} from "vitest";
import {measureMarkdownEditor} from "../bootstrap";

type MeasurementRequest = NonNullable<Parameters<EditorView["requestMeasure"]>[0]>;

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

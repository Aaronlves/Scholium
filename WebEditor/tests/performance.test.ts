import {describe, expect, it, vi} from "vitest";
import {
  clearEditorPerformanceSamples,
  editorPerformanceSamples,
  recordEditorMetric,
  sampleEditorMemory,
  scheduleAfterNextPaint,
} from "../performance";

describe("editor performance instrumentation", () => {
  it("records only bounded numeric metadata", () => {
    clearEditorPerformanceSamples();
    recordEditorMetric("projection", performance.now(), {documentLength: 120, invalid: Number.NaN});
    sampleEditorMemory(120);
    const samples = editorPerformanceSamples();
    expect(samples.at(-2)?.name).toBe("projection");
    expect(samples.at(-2)?.observed).toEqual({documentLength: 120});
    expect(samples.length).toBeLessThanOrEqual(256);
  });

  it("uses a chronological fixed-capacity ring and clears User Timing entries", () => {
    clearEditorPerformanceSamples();
    for (let index = 0; index < 300; index += 1) {
      recordEditorMetric(`sample-${index}`, performance.now());
    }
    const samples = editorPerformanceSamples();
    expect(samples).toHaveLength(256);
    expect(samples[0].name).toBe("sample-44");
    expect(samples.at(-1)?.name).toBe("sample-299");
    expect(performance.getEntriesByName("scholium-editor:sample-299")).toHaveLength(0);
  });

  it("crosses a frame and the following task before reporting painted input", () => {
    const frames: FrameRequestCallback[] = [];
    const tasks: Array<() => void> = [];
    let reported = false;
    scheduleAfterNextPaint(
      () => { reported = true; },
      (callback) => { frames.push(callback); return 1; },
      (callback) => { tasks.push(callback); return 1; },
    );

    expect(reported).toBe(false);
    expect(tasks).toHaveLength(0);
    frames[0](0);
    expect(reported).toBe(false);
    expect(tasks).toHaveLength(1);
    tasks[0]();
    expect(reported).toBe(true);
  });

  it("separates frame scheduling from a delayed following task", () => {
    const frames: FrameRequestCallback[] = [];
    const tasks: Array<() => void> = [];
    const callback = vi.fn();
    const clock = vi.spyOn(performance, "now")
      .mockReturnValueOnce(10).mockReturnValueOnce(12).mockReturnValueOnce(950);
    try {
      scheduleAfterNextPaint(callback,
        frame => { frames.push(frame); return 1; },
        task => { tasks.push(task); return 1; });
      frames[0](0);
      expect(callback).not.toHaveBeenCalled();
      tasks[0]();
      expect(callback).toHaveBeenCalledExactlyOnceWith({frameWaitMilliseconds: 2, taskWaitMilliseconds: 938});
    } finally { clock.mockRestore(); }
  });
});

import {describe, expect, it} from "vitest";
import {
  clearEditorPerformanceSamples,
  editorPerformanceSamples,
  recordEditorMetric,
  sampleEditorMemory,
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
});

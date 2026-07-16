import {describe, expect, it} from "vitest";
import {editorPerformanceSamples, recordEditorMetric, sampleEditorMemory} from "../performance";

describe("editor performance instrumentation", () => {
  it("records only bounded numeric metadata", () => {
    recordEditorMetric("projection", performance.now(), {documentLength: 120, invalid: Number.NaN});
    sampleEditorMemory(120);
    const samples = editorPerformanceSamples();
    expect(samples.at(-2)?.name).toBe("projection");
    expect(samples.at(-2)?.observed).toEqual({documentLength: 120});
    expect(samples.length).toBeLessThanOrEqual(256);
  });
});

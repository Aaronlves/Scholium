export interface EditorPerformanceSample {
  name: string;
  durationMilliseconds: number;
  observed: Record<string, number>;
}

const samples: EditorPerformanceSample[] = [];

export function recordEditorMetric(
  name: string,
  startedAt: number,
  observed: Record<string, number> = {},
) {
  const durationMilliseconds = Math.max(0, performance.now() - startedAt);
  const safeObserved = Object.fromEntries(Object.entries(observed).filter(([, value]) => Number.isFinite(value) && value >= 0));
  samples.push({name, durationMilliseconds, observed: safeObserved});
  if (samples.length > 256) samples.splice(0, samples.length - 256);
  try {
    performance.measure(`scholium-editor:${name}`, {start: startedAt, duration: durationMilliseconds});
  } catch { /* User Timing is diagnostic-only. */ }
}

export function sampleEditorMemory(documentLength: number) {
  const memory = (performance as Performance & {memory?: {usedJSHeapSize?: number}}).memory;
  const usedBytes = memory?.usedJSHeapSize;
  recordEditorMetric("memory-sample", performance.now(), {
    documentLength,
    ...(typeof usedBytes === "number" ? {usedJSHeapBytes: usedBytes} : {}),
  });
}

export function editorPerformanceSamples() {
  return samples.map((sample) => ({...sample, observed: {...sample.observed}}));
}

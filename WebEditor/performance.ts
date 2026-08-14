export interface EditorPerformanceSample {
  name: string;
  durationMilliseconds: number;
  observed: Record<string, number>;
}

const samples: EditorPerformanceSample[] = [];
const sampleCapacity = 256;
let sampleStart = 0;
let sampleCount = 0;

function appendSample(sample: EditorPerformanceSample) {
  if (sampleCount < sampleCapacity) {
    samples[(sampleStart + sampleCount) % sampleCapacity] = sample;
    sampleCount += 1;
    return;
  }
  samples[sampleStart] = sample;
  sampleStart = (sampleStart + 1) % sampleCapacity;
}

export function recordEditorMetric(
  name: string,
  startedAt: number,
  observed: Record<string, number> = {},
) {
  const durationMilliseconds = Math.max(0, performance.now() - startedAt);
  const safeObserved = Object.fromEntries(Object.entries(observed).filter(([, value]) => Number.isFinite(value) && value >= 0));
  appendSample({name, durationMilliseconds, observed: safeObserved});
  const measureName = `scholium-editor:${name}`;
  try {
    performance.measure(measureName, {start: startedAt, duration: durationMilliseconds});
  } catch { /* User Timing is diagnostic-only. */ }
  finally {
    // The bounded Scholium ring is the diagnostic authority. Browser User
    // Timing entries are cleared immediately so a long editing session cannot
    // accumulate an independent, unbounded copy.
    try { performance.clearMeasures(measureName); } catch { /* Diagnostic-only. */ }
  }
}

/// Runs after the browser has received one animation-frame opportunity and
/// crossed into the following task. The frame callback itself runs before
/// paint, so it is not a valid key-to-painted-edit endpoint.
export function scheduleAfterNextPaint(
  callback: () => void,
  requestFrame: (callback: FrameRequestCallback) => number =
    window.requestAnimationFrame.bind(window),
  scheduleTask: (callback: () => void) => number =
    (task) => window.setTimeout(task, 0),
) {
  requestFrame(() => { scheduleTask(callback); });
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
  return Array.from({length: sampleCount}, (_, index) => {
    const sample = samples[(sampleStart + index) % sampleCapacity];
    return {...sample, observed: {...sample.observed}};
  });
}

export function clearEditorPerformanceSamples() {
  samples.length = 0;
  sampleStart = 0;
  sampleCount = 0;
}

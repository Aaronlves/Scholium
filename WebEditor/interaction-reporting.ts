/**
 * Keeps only the latest callback and admits at most one scheduled animation
 * frame. Reader selection changes therefore publish only their latest geometry
 * for the painted frame.
 */
export class AnimationFrameCoalescer {
  private frame: number | null = null;
  private watchdog: number | null = null;
  private latest: (() => void) | null = null;
  private generation = 0;

  constructor(
    private readonly requestFrame: (callback: FrameRequestCallback) => number,
    private readonly cancelFrame: (identifier: number) => void,
    private readonly requestWatchdog: (callback: () => void, delayMilliseconds: number) => number,
    private readonly cancelWatchdog: (identifier: number) => void,
    private readonly watchdogMilliseconds = 50,
  ) {}

  schedule(callback: () => void) {
    this.latest = callback;
    if (this.frame !== null) return;
    const generation = ++this.generation;
    this.frame = this.requestFrame(() => this.flush("frame", generation));
    this.watchdog = this.requestWatchdog(
      () => this.flush("watchdog", generation),
      this.watchdogMilliseconds,
    );
  }

  cancel() {
    if (this.frame !== null) this.cancelFrame(this.frame);
    if (this.watchdog !== null) this.cancelWatchdog(this.watchdog);
    this.frame = null;
    this.watchdog = null;
    this.latest = null;
    this.generation += 1;
  }

  private flush(source: "frame" | "watchdog", generation: number) {
    if (generation !== this.generation) return;
    if (source === "watchdog" && this.frame !== null) this.cancelFrame(this.frame);
    if (source === "frame" && this.watchdog !== null) this.cancelWatchdog(this.watchdog);
    this.frame = null;
    this.watchdog = null;
    const latest = this.latest;
    this.latest = null;
    latest?.();
  }
}

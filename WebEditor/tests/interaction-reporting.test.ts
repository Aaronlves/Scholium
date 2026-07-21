import {describe, expect, it} from "vitest";
import {
  AnimationFrameCoalescer,
  interactionAvailabilitySignature,
} from "../interaction-reporting";

describe("animation-frame interaction reporting", () => {
  it("emits only the latest interaction once per frame", () => {
    const scheduled: FrameRequestCallback[] = [];
    const watchdogs: Array<() => void> = [];
    const observed: number[] = [];
    const coalescer = new AnimationFrameCoalescer(
      (callback) => { scheduled.push(callback); return scheduled.length; },
      () => {},
      (callback) => { watchdogs.push(callback); return watchdogs.length; },
      () => {},
    );

    for (let index = 0; index < 1_000; index += 1) {
      coalescer.schedule(() => observed.push(index));
    }

    expect(scheduled).toHaveLength(1);
    scheduled[0](16);
    expect(observed).toEqual([999]);
  });

  it("uses one latest-value watchdog report when animation frames are throttled", () => {
    const scheduled: FrameRequestCallback[] = [];
    const watchdogs: Array<() => void> = [];
    const canceledFrames: number[] = [];
    const observed: number[] = [];
    const coalescer = new AnimationFrameCoalescer(
      (callback) => { scheduled.push(callback); return scheduled.length; },
      (identifier) => canceledFrames.push(identifier),
      (callback) => { watchdogs.push(callback); return watchdogs.length; },
      () => {},
      50,
    );

    coalescer.schedule(() => observed.push(1));
    coalescer.schedule(() => observed.push(2));
    expect(scheduled).toHaveLength(1);
    expect(watchdogs).toHaveLength(1);

    watchdogs[0]();
    expect(canceledFrames).toEqual([1]);
    expect(observed).toEqual([2]);

    // A canceled frame callback racing with the watchdog must not duplicate
    // the report or consume a newer generation.
    scheduled[0](100);
    expect(observed).toEqual([2]);
  });

  it("publishes availability when a collapsed selection becomes nonempty", () => {
    const context = {
      selections: [{anchor: 4, head: 4}],
      activeInlineConstructs: [],
      activeBlockConstructs: [],
      composing: false,
      availableCommands: [],
    };
    const collapsed = interactionAvailabilitySignature(context);
    const selected = interactionAvailabilitySignature({
      ...context,
      selections: [{anchor: 4, head: 8}],
    });
    expect(selected).not.toBe(collapsed);
  });
});

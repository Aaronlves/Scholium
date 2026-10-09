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

  it("flushes the latest selection before native menu tracking without duplicate scheduled reports", () => {
    const frames: FrameRequestCallback[] = [];
    const watchdogs: Array<() => void> = [];
    const canceled: string[] = [];
    const observed: number[] = [];
    const coalescer = new AnimationFrameCoalescer(
      callback => { frames.push(callback); return frames.length; },
      id => canceled.push(`frame:${id}`),
      callback => { watchdogs.push(callback); return watchdogs.length; },
      id => canceled.push(`watchdog:${id}`),
    );
    coalescer.schedule(() => observed.push(1));
    coalescer.schedule(() => observed.push(2));
    coalescer.flushNow();
    expect(observed).toEqual([2]);
    expect(canceled).toEqual(["frame:1", "watchdog:1"]);
    coalescer.schedule(() => observed.push(3));
    frames[0](16); watchdogs[0]();
    expect(observed).toEqual([2]);
    frames[1](32);
    expect(observed).toEqual([2, 3]);
    coalescer.flushNow();
    expect(observed).toEqual([2, 3]);
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
    expect(interactionAvailabilitySignature({...context, citationState: "stale"})).not.toBe(collapsed);
    expect(interactionAvailabilitySignature({...context, citationState: "unresolved"})).not.toBe(collapsed);
  });
});

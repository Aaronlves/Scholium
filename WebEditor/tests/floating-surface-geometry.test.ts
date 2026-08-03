import {describe, expect, it} from "vitest";
import {floatingSurfacePosition} from "../floating-surface-geometry";

const surface = {width: 120, height: 38};
const viewport = {width: 640, height: 480};

describe("floating surface geometry", () => {
  it("centers a selection control above its anchor", () => {
    expect(floatingSurfacePosition({
      anchor: {left: 220, right: 300, top: 180, bottom: 202},
      surface,
      viewport,
      horizontal: "center",
      preferredPlacement: "above",
      inset: 8,
      gap: 6,
    })).toEqual({left: 200, top: 136, placement: "above"});
  });

  it("moves a selection control below when the space above is insufficient", () => {
    expect(floatingSurfacePosition({
      anchor: {left: 220, right: 300, top: 28, bottom: 50},
      surface,
      viewport,
      horizontal: "center",
      preferredPlacement: "above",
      inset: 8,
      gap: 6,
    })).toEqual({left: 200, top: 56, placement: "below"});
  });

  it("clamps centered and start-aligned panels to the viewport", () => {
    expect(floatingSurfacePosition({
      anchor: {left: 4, right: 24, top: 160, bottom: 180},
      surface,
      viewport,
      horizontal: "center",
      preferredPlacement: "above",
      inset: 12,
      gap: 8,
    }).left).toBe(12);
    expect(floatingSurfacePosition({
      anchor: {left: 610, right: 630, top: 160, bottom: 180},
      surface,
      viewport,
      horizontal: "start",
      preferredPlacement: "below",
      inset: 12,
      gap: 8,
    })).toEqual({left: 508, top: 188, placement: "below"});
  });
});

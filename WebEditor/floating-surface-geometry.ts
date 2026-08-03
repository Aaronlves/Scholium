export interface FloatingSurfaceRect {
  readonly left: number;
  readonly right: number;
  readonly top: number;
  readonly bottom: number;
}

export interface FloatingSurfaceSize {
  readonly width: number;
  readonly height: number;
}

export interface FloatingViewportSize {
  readonly width: number;
  readonly height: number;
}

export interface FloatingSurfacePosition {
  readonly left: number;
  readonly top: number;
  readonly placement: "above" | "below";
}

function clamped(value: number, minimum: number, maximum: number) {
  return Math.max(minimum, Math.min(value, Math.max(minimum, maximum)));
}

/**
 * Resolves viewport-clamped geometry only. The calling surface retains its
 * own anchor lifetime, measurement phase, focus, dismissal, and DOM owner.
 */
export function floatingSurfacePosition(options: {
  anchor: FloatingSurfaceRect;
  surface: FloatingSurfaceSize;
  viewport: FloatingViewportSize;
  horizontal: "center" | "start";
  preferredPlacement: "above" | "below";
  inset: number;
  gap: number;
}): FloatingSurfacePosition {
  const {anchor, surface, viewport, inset, gap} = options;
  const desiredLeft = options.horizontal === "center"
    ? (anchor.left + anchor.right - surface.width) / 2
    : anchor.left;
  const left = clamped(desiredLeft, inset, viewport.width - surface.width - inset);
  const above = anchor.top - surface.height - gap;
  const below = anchor.bottom + gap;
  const fitsAbove = above >= inset;
  const fitsBelow = below + surface.height <= viewport.height - inset;

  if (options.preferredPlacement === "above") {
    if (fitsAbove) return {left, top: above, placement: "above"};
    if (fitsBelow) return {left, top: below, placement: "below"};
    return {
      left,
      top: clamped(above, inset, viewport.height - surface.height - inset),
      placement: "above",
    };
  }
  if (fitsBelow) return {left, top: below, placement: "below"};
  if (fitsAbove) return {left, top: above, placement: "above"};
  return {
    left,
    top: clamped(below, inset, viewport.height - surface.height - inset),
    placement: "below",
  };
}

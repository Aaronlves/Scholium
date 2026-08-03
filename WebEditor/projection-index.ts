export interface ImmutableProjectionRange {
  readonly from: number;
  readonly to: number;
}

function compareRanges(left: ImmutableProjectionRange, right: ImmutableProjectionRange) {
  return left.from - right.from || left.to - right.to;
}

const prefixMaximumEnds = new WeakMap<object, readonly number[]>();

function maximumEndsFor(ranges: readonly ImmutableProjectionRange[]) {
  const cached = prefixMaximumEnds.get(ranges);
  if (cached) return cached;
  let maximum = -1;
  const values = Object.freeze(ranges.map((range) => {
    maximum = Math.max(maximum, range.to);
    return maximum;
  }));
  prefixMaximumEnds.set(ranges, values);
  return values;
}

/**
 * Owns a sorted, immutable copy of projection ranges. Query callers never
 * receive the mutable arrays used while a syntax index is being assembled.
 */
export function immutableProjectionRanges<T extends ImmutableProjectionRange>(
  ranges: readonly T[],
): readonly Readonly<T>[] {
  const immutable = Object.freeze(ranges
    .map((range) => Object.freeze({...range}))
    .sort(compareRanges));
  maximumEndsFor(immutable);
  return immutable;
}

export function commandProtectionRanges(
  literalRanges: readonly ImmutableProjectionRange[],
  frontmatterRange?: ImmutableProjectionRange,
) {
  return immutableProjectionRanges(frontmatterRange
    ? [...literalRanges, frontmatterRange]
    : literalRanges);
}

/** Returns ranges overlapping the half-open query without scanning a prefix. */
export function projectionRangesIntersecting<T extends ImmutableProjectionRange>(
  ranges: readonly T[],
  from: number,
  to: number,
): readonly T[] {
  // Locate the last possible overlap by `from`, then use cached prefix-max
  // ends to stop the backward walk before unrelated earlier ranges. Unlike a
  // binary search over `to`, this remains correct for nested intervals.
  let low = 0;
  let high = ranges.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (ranges[middle].from < to) low = middle + 1;
    else high = middle;
  }
  const maximumEnds = maximumEndsFor(ranges);
  const matches: T[] = [];
  for (let index = low - 1; index >= 0 && maximumEnds[index] > from; index -= 1) {
    if (ranges[index].to > from) matches.push(ranges[index]);
  }
  matches.reverse();
  return matches;
}

/** Finds the one sorted structural range containing a caret offset. */
export function projectionRangeContaining<T extends ImmutableProjectionRange>(
  ranges: readonly T[],
  offset: number,
): T | null {
  const candidates = projectionRangesIntersecting(ranges, offset, offset + 1);
  return candidates[0] ?? null;
}

/** Finds a range whose exact start or end owns one navigation boundary. */
export function projectionRangeAtBoundary<T extends ImmutableProjectionRange>(
  ranges: readonly T[],
  offset: number,
  boundary: "start" | "end",
): T | null {
  const candidates = projectionRangesIntersecting(
    ranges,
    Math.max(0, offset - 1),
    offset + 1,
  );
  return candidates.find((range) =>
    boundary === "start" ? range.from === offset : range.to === offset,
  ) ?? null;
}

export function projectionSelectionOverlaps(
  ranges: readonly ImmutableProjectionRange[],
  selection: ImmutableProjectionRange,
) {
  if (selection.from === selection.to) {
    return projectionRangeContaining(ranges, selection.from) !== null;
  }
  return projectionRangesIntersecting(ranges, selection.from, selection.to).length > 0;
}

/**
 * Tests the inclusive edit boundary used by projection mapping without an
 * O(n) scan. An insertion immediately after a construct remains conservative:
 * it may extend that Markdown construct and therefore still touches it.
 */
export function projectionBoundaryTouches(
  ranges: readonly ImmutableProjectionRange[],
  offset: number,
) {
  const candidates = projectionRangesIntersecting(
    ranges,
    Math.max(0, offset - 1),
    offset + 1,
  );
  return candidates.some((range) => offset >= range.from && offset <= range.to);
}

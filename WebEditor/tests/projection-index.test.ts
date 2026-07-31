import {describe, expect, it} from "vitest";
import {
  commandProtectionRanges,
  immutableProjectionRanges,
  projectionBoundaryTouches,
  projectionRangeContaining,
  projectionRangesIntersecting,
  projectionSelectionOverlaps,
} from "../projection-index";

describe("immutable live projection range index", () => {
  it("keeps frontmatter and literal cardinality constant across 10,000 queries", () => {
    const literals = [{from: 40, to: 55}, {from: 80, to: 90}];
    const ranges = commandProtectionRanges(literals, {from: 0, to: 24});

    for (let query = 0; query < 10_000; query += 1) {
      expect(projectionSelectionOverlaps(ranges, {from: query % 100, to: query % 100}))
        .toBeTypeOf("boolean");
    }

    expect(ranges).toEqual([
      {from: 0, to: 24},
      {from: 40, to: 55},
      {from: 80, to: 90},
    ]);
    expect(ranges).toHaveLength(3);
    expect(Object.isFrozen(ranges)).toBe(true);
    expect(ranges.every(Object.isFrozen)).toBe(true);
  });

  it("uses binary interval queries at exact half-open boundaries", () => {
    const ranges = commandProtectionRanges([{from: 10, to: 20}, {from: 30, to: 40}]);
    expect(projectionRangeContaining(ranges, 10)).toEqual({from: 10, to: 20});
    expect(projectionRangeContaining(ranges, 20)).toBeNull();
    expect(projectionRangesIntersecting(ranges, 18, 32)).toEqual(ranges);
  });

  it("does not skip an enclosing range when later ranges end earlier", () => {
    const ranges = commandProtectionRanges([
      {from: 0, to: 100},
      {from: 10, to: 20},
      {from: 30, to: 40},
    ]);
    expect(projectionRangesIntersecting(ranges, 80, 81)).toEqual([{from: 0, to: 100}]);
    expect(projectionRangeContaining(ranges, 100)).toBeNull();
  });

  it("reuses one immutable block index across 1,000 arrow-neighbor queries", () => {
    const ranges = immutableProjectionRanges(Array.from({length: 10_000}, (_, index) => ({
      from: index * 20,
      to: index * 20 + 10,
    })));
    let matches = 0;
    for (let index = 0; index < 1_000; index += 1) {
      const head = index * 20;
      matches += projectionRangesIntersecting(ranges, Math.max(0, head - 1), head + 1).length;
    }
    expect(matches).toBe(1_000);
    expect(Object.isFrozen(ranges)).toBe(true);
    expect(ranges).toHaveLength(10_000);
  });

  it("uses the same index for inclusive edit-boundary checks", () => {
    const ranges = immutableProjectionRanges(Array.from({length: 10_000}, (_, index) => ({
      from: index * 20,
      to: index * 20 + 10,
    })));
    expect(projectionBoundaryTouches(ranges, 0)).toBe(true);
    expect(projectionBoundaryTouches(ranges, 10)).toBe(true);
    expect(projectionBoundaryTouches(ranges, 11)).toBe(false);
    expect(projectionBoundaryTouches(ranges, 199_990)).toBe(true);
  });
});

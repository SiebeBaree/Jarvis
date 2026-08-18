import { describe, expect, it } from "vitest";
import { estimateOneRepMax, volumeOf, workingSetCount } from "../src/lib/training-math";

const set = (over: Partial<{ weightKg: number | null; reps: number | null; isWarmup: boolean }> = {}) => ({
  weightKg: 100 as number | null,
  reps: 5 as number | null,
  isWarmup: false,
  ...over,
});

describe("estimated one-rep max", () => {
  it("returns the bare weight for a single", () => {
    expect(estimateOneRepMax(100, 1)).toBeCloseTo(103.33, 2);
  });

  it("ranks a heavier short set above a lighter long one when it should", () => {
    expect(estimateOneRepMax(100, 5)).toBeGreaterThan(estimateOneRepMax(80, 8));
  });

  it("ranks a lighter long set above a heavier short one when it should", () => {
    expect(estimateOneRepMax(80, 12)).toBeGreaterThan(estimateOneRepMax(90, 5));
  });

  it("is zero for sets that carry no usable numbers", () => {
    expect(estimateOneRepMax(null, 5)).toBe(0);
    expect(estimateOneRepMax(100, null)).toBe(0);
    expect(estimateOneRepMax(100, 0)).toBe(0);
  });

  it("handles bodyweight work without inventing a weight", () => {
    expect(estimateOneRepMax(0, 12)).toBe(0);
  });
});

describe("volume", () => {
  it("multiplies weight by reps across working sets", () => {
    expect(volumeOf([set(), set({ reps: 8 })])).toBe(1300);
  });

  it("excludes warm-ups", () => {
    expect(volumeOf([set(), set({ isWarmup: true, weightKg: 60, reps: 10 })])).toBe(500);
    expect(workingSetCount([set(), set({ isWarmup: true })])).toBe(1);
  });

  it("treats missing numbers as zero rather than NaN", () => {
    expect(volumeOf([set({ weightKg: null }), set({ reps: null })])).toBe(0);
  });

  it("rounds to one decimal so 2.5 kg plates do not produce float noise", () => {
    expect(volumeOf([set({ weightKg: 2.5, reps: 3 })])).toBe(7.5);
  });
});

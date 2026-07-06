import { describe, expect, it } from "vitest";
import {
  computeMomentum,
  creditForBinary,
  creditForQuantity,
  type MomentumHabitInput,
} from "../momentum";

describe("computeMomentum", () => {
  it("returns null for empty input (rest day)", () => {
    expect(computeMomentum([])).toBeNull();
  });

  it("scores a fully completed set as 100", () => {
    const habits: MomentumHabitInput[] = [
      { weight: 1, credit: 1 },
      { weight: 2, credit: 1 },
      { weight: 3, credit: 1 },
    ];
    expect(computeMomentum(habits)).toEqual({
      score: 100,
      completedWeight: 6,
      scheduledWeight: 6,
    });
  });

  it("scores a fully missed set as 0", () => {
    const habits: MomentumHabitInput[] = [
      { weight: 1, credit: 0 },
      { weight: 3, credit: 0 },
    ];
    expect(computeMomentum(habits)).toEqual({
      score: 0,
      completedWeight: 0,
      scheduledWeight: 4,
    });
  });

  it("respects weights (heavier habits move the score more)", () => {
    // completed weight-3 habit, missed weight-1 habit -> 3/4 = 75
    const habits: MomentumHabitInput[] = [
      { weight: 3, credit: 1 },
      { weight: 1, credit: 0 },
    ];
    expect(computeMomentum(habits)?.score).toBe(75);
  });

  it("supports partial credit", () => {
    const habits: MomentumHabitInput[] = [
      { weight: 2, credit: 0.5 },
      { weight: 2, credit: 1 },
    ];
    // (0.5*2 + 1*2) / 4 = 3/4 = 75
    const result = computeMomentum(habits);
    expect(result?.score).toBe(75);
    expect(result?.completedWeight).toBe(3);
    expect(result?.scheduledWeight).toBe(4);
  });

  it("rounds to the nearest integer", () => {
    // 1/3 = 33.33 -> 33
    expect(computeMomentum([{ weight: 1, credit: 1 / 3 }])?.score).toBe(33);
    // 2/3 = 66.67 -> 67
    expect(computeMomentum([{ weight: 1, credit: 2 / 3 }])?.score).toBe(67);
    // 0.005 -> round(0.5) = 1 (round-half-up)
    expect(computeMomentum([{ weight: 1, credit: 0.005 }])?.score).toBe(1);
  });

  it("clamps out-of-range credit values", () => {
    expect(
      computeMomentum([{ weight: 1, credit: 5 }])?.completedWeight,
    ).toBe(1);
    expect(
      computeMomentum([{ weight: 2, credit: -3 }])?.completedWeight,
    ).toBe(0);
  });
});

describe("creditForBinary", () => {
  it("returns 1 when completed, 0 otherwise", () => {
    expect(creditForBinary(true)).toBe(1);
    expect(creditForBinary(false)).toBe(0);
  });
});

describe("creditForQuantity", () => {
  it("returns logged/target capped at 1", () => {
    expect(creditForQuantity(5, 10)).toBe(0.5);
    expect(creditForQuantity(10, 10)).toBe(1);
    expect(creditForQuantity(15, 10)).toBe(1);
  });

  it("guards target <= 0 -> 0", () => {
    expect(creditForQuantity(5, 0)).toBe(0);
    expect(creditForQuantity(5, -2)).toBe(0);
  });

  it("clamps negative logged values to 0", () => {
    expect(creditForQuantity(-3, 10)).toBe(0);
  });
});

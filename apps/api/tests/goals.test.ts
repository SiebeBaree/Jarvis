import { describe, expect, it } from "vitest";
import { goalProgress, type GoalLike, type MilestoneLike } from "../src/lib/goals";

const goal = (over: Partial<GoalLike> = {}): GoalLike => ({
  startDate: "2026-01-01",
  targetDate: "2026-12-31", // 365 days inclusive
  startValue: null,
  targetValue: null,
  currentValue: null,
  ...over,
});

const done = (): MilestoneLike => ({ goalId: "g", doneAt: new Date() });
const open = (): MilestoneLike => ({ goalId: "g", doneAt: null });

describe("time progress", () => {
  it("is 0 on the start day and ~1 at the target", () => {
    expect(goalProgress(goal(), [], "2026-01-01").timeProgress).toBe(0);
    expect(goalProgress(goal(), [], "2026-12-31").timeProgress).toBeCloseTo(0.997, 2);
  });

  it("clamps past the target date instead of running over 100%", () => {
    const p = goalProgress(goal(), [], "2027-06-01");
    expect(p.timeProgress).toBe(1);
    expect(p.daysRemaining).toBeLessThan(0);
  });

  it("reports days remaining inclusive of the window", () => {
    const p = goalProgress(goal(), [], "2026-12-01");
    expect(p.daysTotal).toBe(365);
    expect(p.daysRemaining).toBe(30);
  });

  it("never divides by zero on a same-day goal", () => {
    const p = goalProgress(goal({ targetDate: "2026-01-01" }), [], "2026-01-01");
    expect(p.daysTotal).toBe(1);
    expect(p.timeProgress).toBe(0);
  });
});

describe("numeric progress", () => {
  it("measures upward goals from the baseline", () => {
    const p = goalProgress(
      goal({ startValue: 0, targetValue: 10_000, currentValue: 3400 }),
      [],
      "2026-06-01",
    );
    expect(p.tracking).toBe("numeric");
    expect(p.progress).toBeCloseTo(0.34, 5);
  });

  it("measures downward goals the same way", () => {
    const p = goalProgress(
      goal({ startValue: 92, targetValue: 80, currentValue: 86 }),
      [],
      "2026-06-01",
    );
    expect(p.progress).toBeCloseTo(0.5, 5);
  });

  it("sits at 0 before the first reading", () => {
    expect(
      goalProgress(goal({ startValue: 0, targetValue: 100, currentValue: null }), [], "2026-06-01")
        .progress,
    ).toBe(0);
  });

  it("clamps overshoot and backslide into [0,1]", () => {
    const over = goal({ startValue: 0, targetValue: 100, currentValue: 140 });
    const under = goal({ startValue: 0, targetValue: 100, currentValue: -20 });
    expect(goalProgress(over, [], "2026-06-01").progress).toBe(1);
    expect(goalProgress(under, [], "2026-06-01").progress).toBe(0);
  });
});

describe("milestone progress", () => {
  it("falls back to the fraction of milestones done", () => {
    const p = goalProgress(goal(), [done(), done(), done(), open(), open()], "2026-06-01");
    expect(p.tracking).toBe("milestones");
    expect(p.progress).toBeCloseTo(0.6, 5);
    expect(p.milestonesDone).toBe(3);
    expect(p.milestonesTotal).toBe(5);
  });

  it("loses to a numeric target when both are present", () => {
    const p = goalProgress(
      goal({ startValue: 0, targetValue: 10, currentValue: 1 }),
      [done(), done()],
      "2026-06-01",
    );
    expect(p.tracking).toBe("numeric");
    expect(p.progress).toBeCloseTo(0.1, 5);
    expect(p.milestonesDone).toBe(2); // still reported, just not the headline
  });

  it("reports no progress at all for an untracked goal", () => {
    const p = goalProgress(goal(), [], "2026-06-01");
    expect(p.tracking).toBe("none");
    expect(p.progress).toBeNull();
  });
});

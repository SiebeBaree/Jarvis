import { describe, expect, it } from "vitest";
import { addDays } from "../src/lib/daykey";
import {
  computeDailyScore,
  dailyStreak,
  feelRaw,
  habitComponentRaw,
  habitCredit,
  paceStatus,
  taskComponent,
  taskCredit,
  weeklyStreak,
  type TaskForScoring,
} from "../src/lib/scoring/engine";

const WEIGHTS = { tasks: 40, habits: 40, feel: 20 };

function task(overrides: Partial<TaskForScoring>): TaskForScoring {
  return {
    id: "t1",
    status: "open",
    subtasks: [],
    completedDayKey: null,
    dueDate: "2026-07-10",
    ...overrides,
  };
}

describe("taskCredit", () => {
  it("is binary for leaf tasks", () => {
    expect(taskCredit(task({ status: "done" }))).toBe(1);
    expect(taskCredit(task({ status: "open" }))).toBe(0);
  });

  it("is the subtask fraction for parents", () => {
    const t = task({
      subtasks: [{ status: "done" }, { status: "done" }, { status: "open" }, { status: "open" }],
    });
    expect(taskCredit(t)).toBe(0.5);
  });

  it("excludes cancelled subtasks from the fraction", () => {
    const t = task({
      subtasks: [{ status: "done" }, { status: "cancelled" }, { status: "open" }],
    });
    expect(taskCredit(t)).toBe(0.5);
  });
});

describe("taskComponent", () => {
  it("is not applicable with no tasks due", () => {
    expect(taskComponent([]).raw).toBeNull();
  });

  it("excludes cancelled tasks entirely", () => {
    const result = taskComponent([task({ status: "cancelled" })]);
    expect(result.raw).toBeNull();
  });

  it("averages credit and flags late completions", () => {
    const result = taskComponent([
      task({ id: "a", status: "done", completedDayKey: "2026-07-10" }),
      task({ id: "b", status: "done", completedDayKey: "2026-07-12" }), // completed 2 days late
      task({ id: "c", status: "open" }),
    ]);
    expect(result.raw).toBeCloseTo(2 / 3);
    expect(result.perTask.find((t) => t.taskId === "a")?.late).toBe(false);
    expect(result.perTask.find((t) => t.taskId === "b")?.late).toBe(true);
  });
});

describe("habitCredit", () => {
  it("daily: binary on any rep", () => {
    expect(habitCredit({ type: "daily", targetReps: 1, repsToday: 0, isLive: true }).credit).toBe(0);
    expect(habitCredit({ type: "daily", targetReps: 1, repsToday: 1, isLive: true }).credit).toBe(1);
    expect(habitCredit({ type: "daily", targetReps: 1, repsToday: 3, isLive: true }).credit).toBe(1);
  });

  it("multi_daily: proportional (1 of 2 = 50%)", () => {
    expect(habitCredit({ type: "multi_daily", targetReps: 2, repsToday: 1, isLive: true }).credit).toBe(0.5);
    expect(habitCredit({ type: "multi_daily", targetReps: 2, repsToday: 2, isLive: true }).credit).toBe(1);
    expect(habitCredit({ type: "multi_daily", targetReps: 3, repsToday: 2, isLive: true }).credit).toBeCloseTo(2 / 3);
  });

  it("weekly live: an unspent day costs nothing while the target is still reachable", () => {
    // Gym 5x/week, Monday, nothing done. Six days left is five sessions and
    // one to spare, so the week can still finish perfect and Monday scores 1.
    const monday = habitCredit({
      type: "weekly_frequency",
      targetReps: 5,
      repsToday: 0,
      doneThroughDay: 0,
      elapsedDayOfWeek: 1,
      isLive: true,
    });
    expect(monday.credit).toBe(1);
    expect(monday.expected).toBe(0);

    // Clean the apartment 1x/week, done on Sunday: every earlier day of that
    // week sits at 1 the whole time, not at 0.
    const chore = habitCredit({
      type: "weekly_frequency",
      targetReps: 1,
      repsToday: 0,
      doneThroughDay: 0,
      elapsedDayOfWeek: 2,
      isLive: true,
    });
    expect(chore.credit).toBe(1);

    // Wednesday with 0 of 5 done: only Thu–Sun remain, so 4 is the best this
    // week can reach and the day carries that ceiling, not a pace penalty.
    const shortfall = habitCredit({
      type: "weekly_frequency",
      targetReps: 5,
      repsToday: 0,
      doneThroughDay: 0,
      elapsedDayOfWeek: 3,
      isLive: true,
    });
    expect(shortfall.credit).toBeCloseTo(0.8);
    expect(shortfall.expected).toBe(1); // one session by tonight keeps 5 alive

    // Same Wednesday, one session banked: 1 + 4 remaining days = 5, still perfect.
    const onTrack = habitCredit({
      type: "weekly_frequency",
      targetReps: 5,
      repsToday: 0,
      doneThroughDay: 1,
      elapsedDayOfWeek: 3,
      isLive: true,
    });
    expect(onTrack.credit).toBe(1);
  });

  it("weekly live: Sunday already equals the reconciled value", () => {
    for (const done of [0, 2, 5, 6]) {
      const live = habitCredit({
        type: "weekly_frequency",
        targetReps: 5,
        repsToday: 0,
        doneThroughDay: done,
        elapsedDayOfWeek: 7,
        isLive: true,
      });
      const final = habitCredit({
        type: "weekly_frequency",
        targetReps: 5,
        repsToday: 0,
        weekTotal: done,
        isLive: false,
      });
      expect(live.credit).toBeCloseTo(final.credit);
    }
  });

  it("weekly reconciled: uniform weekly-total credit — back-loading scores identically", () => {
    // Week over. 5 sessions Tue–Sat (none Monday) must equal an on-plan week.
    const backloaded = habitCredit({
      type: "weekly_frequency",
      targetReps: 5,
      repsToday: 0,
      weekTotal: 5,
      isLive: false,
    });
    expect(backloaded.credit).toBe(1);
    expect(backloaded.reconciled).toBe(true);

    // Shortfall (3 of 5) → every day of that week carries 0.6.
    const short = habitCredit({
      type: "weekly_frequency",
      targetReps: 5,
      repsToday: 0,
      weekTotal: 3,
      isLive: false,
    });
    expect(short.credit).toBeCloseTo(0.6);
  });
});

describe("habitComponentRaw / feelRaw", () => {
  it("means credits; not applicable when empty", () => {
    expect(habitComponentRaw([])).toBeNull();
    expect(habitComponentRaw([1, 0.5])).toBe(0.75);
  });

  it("clamps mood to 0-100", () => {
    expect(feelRaw(null)).toBeNull();
    expect(feelRaw(72)).toBe(0.72);
    expect(feelRaw(150)).toBe(1);
  });
});

describe("computeDailyScore", () => {
  it("computes the full-weight case", () => {
    const r = computeDailyScore({
      weights: WEIGHTS,
      taskRaw: 5 / 7,
      habitRaw: 0.8,
      feelRaw: 0.72,
    });
    expect(r.applicableWeight).toBe(100);
    expect(r.taskPoints).toBeCloseTo(28.57, 1);
    expect(r.habitPoints).toBe(32);
    expect(r.feelPoints).toBe(14.4);
    expect(r.total).toBeCloseTo(28.57 + 32 + 14.4, 0);
  });

  it("renormalizes over 80 when mood is missing", () => {
    const r = computeDailyScore({
      weights: WEIGHTS,
      taskRaw: 0.5,
      habitRaw: 1,
      feelRaw: null,
    });
    expect(r.applicableWeight).toBe(80);
    expect(r.total).toBe(75); // (20 + 40) / 80 * 100
    expect(r.feelPoints).toBeNull();
  });

  it("drops tasks from the denominator when none are due", () => {
    const r = computeDailyScore({
      weights: WEIGHTS,
      taskRaw: null,
      habitRaw: 0.5,
      feelRaw: 1,
    });
    expect(r.applicableWeight).toBe(60);
    expect(r.total).toBeCloseTo(((40 * 0.5 + 20) / 60) * 100, 1);
  });

  it("returns null (not 0) when nothing is applicable", () => {
    const r = computeDailyScore({
      weights: WEIGHTS,
      taskRaw: null,
      habitRaw: null,
      feelRaw: null,
    });
    expect(r.total).toBeNull();
    expect(r.applicableWeight).toBe(0);
  });
});

describe("streaks", () => {
  it("daily: incomplete today does not break the streak", () => {
    const qualifying = new Set(["2026-07-07", "2026-07-08", "2026-07-09"]);
    expect(dailyStreak(qualifying, "2026-07-10", addDays).current).toBe(3);
  });

  it("daily: today completing extends the streak", () => {
    const qualifying = new Set(["2026-07-08", "2026-07-09", "2026-07-10"]);
    expect(dailyStreak(qualifying, "2026-07-10", addDays).current).toBe(3);
  });

  it("daily: a gap resets current but best remembers", () => {
    const qualifying = new Set([
      "2026-07-01",
      "2026-07-02",
      "2026-07-03",
      "2026-07-04",
      // gap on 07-05
      "2026-07-09",
    ]);
    const r = dailyStreak(qualifying, "2026-07-10", addDays);
    expect(r.current).toBe(1);
    expect(r.best).toBe(4);
  });

  it("weekly: in-progress week ignored unless already met", () => {
    const qualifying = new Set(["2026-06-22", "2026-06-29"]); // two completed weeks
    // Current week (2026-07-06) not yet qualifying → streak counts back from last week.
    expect(weeklyStreak(qualifying, "2026-07-06", addDays).current).toBe(2);
    // Current week already met → extends immediately.
    const withCurrent = new Set([...qualifying, "2026-07-06"]);
    expect(weeklyStreak(withCurrent, "2026-07-06", addDays).current).toBe(3);
  });
});

describe("paceStatus (display rule)", () => {
  it("never calls you behind early in the morning", () => {
    // Wednesday 7 AM, gym 5x/week, 2 of 5 done.
    // Elapsed full days = 2 (Mon, Tue) → expected = ceil(10/7) = 2 → on pace.
    const morning = paceStatus({ targetReps: 5, weekTotal: 2, elapsedDayOfWeek: 3, hourOfDay: 7 });
    expect(morning).toEqual({ kind: "on_pace" });
  });

  it("counts today as elapsed from 18:00", () => {
    // Wednesday 19:00: expected = ceil(15/7) = 3 → 2 done = behind by 1.
    const evening = paceStatus({ targetReps: 5, weekTotal: 2, elapsedDayOfWeek: 3, hourOfDay: 19 });
    expect(evening).toEqual({ kind: "behind", by: 1 });
  });

  it("reports week done and out of reach", () => {
    expect(paceStatus({ targetReps: 5, weekTotal: 5, elapsedDayOfWeek: 6, hourOfDay: 12 })).toEqual({
      kind: "week_done",
    });
    // Saturday morning, 1 of 5 done, remaining days (Sat+Sun) = 2 < 4 needed.
    expect(paceStatus({ targetReps: 5, weekTotal: 1, elapsedDayOfWeek: 6, hourOfDay: 12 })).toEqual({
      kind: "out_of_reach",
    });
  });
});

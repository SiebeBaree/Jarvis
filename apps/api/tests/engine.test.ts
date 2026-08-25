import { describe, expect, it } from "vitest";
import {
  computeDailyScore,
  feelRaw,
  habitComponentRaw,
  habitCredit,
  paceStatus,
  taskComponent,
  taskCredit,
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

describe("paceStatus (display rule)", () => {
  it("stays on track while the target is still reachable", () => {
    // Gym 5x/week. Tuesday skipped, so Wednesday has 1 done and 5 days left.
    expect(paceStatus({ targetReps: 5, weekTotal: 1, elapsedDayOfWeek: 3 })).toEqual({
      kind: "on_track",
      remaining: 4,
      daysLeft: 5,
    });
  });

  it("does not call a once-a-week habit late on Tuesday", () => {
    expect(paceStatus({ targetReps: 1, weekTotal: 0, elapsedDayOfWeek: 2 })).toEqual({
      kind: "on_track",
      remaining: 1,
      daysLeft: 6,
    });
  });

  it("flags the last chance when every remaining day is needed", () => {
    // Saturday, 3 of 5 done: Saturday and Sunday both have to count.
    expect(paceStatus({ targetReps: 5, weekTotal: 3, elapsedDayOfWeek: 6 })).toEqual({
      kind: "last_chance",
      remaining: 2,
      daysLeft: 2,
    });
    // Sunday of a once-a-week habit: today or never.
    expect(paceStatus({ targetReps: 1, weekTotal: 0, elapsedDayOfWeek: 7 })).toEqual({
      kind: "last_chance",
      remaining: 1,
      daysLeft: 1,
    });
  });

  it("reports week done and out of reach", () => {
    expect(paceStatus({ targetReps: 5, weekTotal: 5, elapsedDayOfWeek: 6 })).toEqual({
      kind: "week_done",
    });
    // Saturday, 1 of 5 done: 4 needed with only Saturday and Sunday left.
    expect(paceStatus({ targetReps: 5, weekTotal: 1, elapsedDayOfWeek: 6 })).toEqual({
      kind: "out_of_reach",
      remaining: 4,
      daysLeft: 2,
    });
  });

  it("agrees with the scoring engine about when credit is lost", () => {
    // The chip leaves "on track" exactly when the day's live credit drops
    // below 1, which is the day the rep has to land or the week is short.
    for (let day = 1; day <= 7; day++) {
      for (let done = 0; done <= 5; done++) {
        const pace = paceStatus({ targetReps: 5, weekTotal: done, elapsedDayOfWeek: day });
        const { credit } = habitCredit({
          type: "weekly_frequency",
          targetReps: 5,
          repsToday: 0,
          doneThroughDay: done,
          weekTotal: done,
          elapsedDayOfWeek: day,
          isLive: true,
        });
        const urgent = pace.kind === "last_chance" || pace.kind === "out_of_reach";
        expect(urgent).toBe(credit < 1);
      }
    }
  });
});

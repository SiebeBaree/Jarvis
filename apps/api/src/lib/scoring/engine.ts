// Pure scoring functions — no database access. See docs/spec.md §A4.
//
// Components produce a raw value in [0,1] or NOT_APPLICABLE (null). The total
// renormalizes over the weights of applicable components only, so a day with
// no tasks due is neither a free 40 points nor a penalty, and a missing mood
// entry renormalizes the score over the remaining 80 points.

import type { ScoreWeights } from "../../db/schema";

export type HabitTypeName = "daily" | "multi_daily" | "weekly_frequency";

// ---------- tasks ----------

export interface TaskForScoring {
  id: string;
  status: "open" | "done" | "cancelled";
  /** Non-cancelled subtasks. Empty for leaf tasks. */
  subtasks: { status: "open" | "done" | "cancelled" }[];
  /** dayKey the task was completed on (null if open). Used for the `late` flag. */
  completedDayKey: string | null;
  dueDate: string;
}

/** Credit for one task: subtask fraction for parents, else binary. */
export function taskCredit(task: TaskForScoring): number {
  const counted = task.subtasks.filter((s) => s.status !== "cancelled");
  if (counted.length > 0) {
    return counted.filter((s) => s.status === "done").length / counted.length;
  }
  return task.status === "done" ? 1 : 0;
}

export interface TaskComponentResult {
  raw: number | null; // null = not applicable (no tasks due)
  perTask: { taskId: string; credit: number; late: boolean }[];
}

/**
 * Task component for a day: mean credit over top-level, non-cancelled tasks
 * due that dayKey. Overdue tasks count only against their original due date;
 * completing one late retro-credits that day (flagged `late`).
 */
export function taskComponent(tasksDue: TaskForScoring[]): TaskComponentResult {
  const counted = tasksDue.filter((t) => t.status !== "cancelled");
  if (counted.length === 0) return { raw: null, perTask: [] };
  const perTask = counted.map((t) => ({
    taskId: t.id,
    credit: taskCredit(t),
    late: t.completedDayKey !== null && t.completedDayKey > t.dueDate,
  }));
  const sum = perTask.reduce((acc, t) => acc + t.credit, 0);
  return { raw: sum / counted.length, perTask };
}

// ---------- habits ----------

export interface HabitCreditInput {
  type: HabitTypeName;
  targetReps: number;
  /** Reps logged on the day being scored (daily / multi_daily). */
  repsToday: number;
  /** weekly_frequency only: reps from the week's Monday through the scored day. */
  doneThroughDay?: number;
  /** weekly_frequency only: reps over the whole week (Mon–Sun). */
  weekTotal?: number;
  /** weekly_frequency only: Mon=1 .. Sun=7 of the scored day. */
  elapsedDayOfWeek?: number;
  /**
   * true while the scored day's week is still running (live pace credit);
   * false once the week has fully ended (uniform weekly-total reconciliation).
   */
  isLive: boolean;
}

export interface HabitCreditResult {
  credit: number; // 0..1
  expected: number; // reps expected by this point (for the breakdown)
  reconciled: boolean;
}

export function habitCredit(input: HabitCreditInput): HabitCreditResult {
  const target = Math.max(1, input.targetReps);
  switch (input.type) {
    case "daily":
      return { credit: Math.min(1, input.repsToday), expected: 1, reconciled: false };
    case "multi_daily":
      return {
        credit: Math.min(1, input.repsToday / target),
        expected: target,
        reconciled: false,
      };
    case "weekly_frequency": {
      if (input.isLive) {
        const elapsed = input.elapsedDayOfWeek ?? 7;
        const expected = (target * elapsed) / 7; // target >= 1 ⇒ expected > 0
        const done = input.doneThroughDay ?? 0;
        return { credit: Math.min(1, done / expected), expected, reconciled: false };
      }
      // Week over: every day of the week reconciles to the uniform weekly-total
      // credit, so back-loading (5 gym sessions Tue–Sat) scores identically to
      // an on-plan week. plannedDays never enter scoring.
      const weekTotal = input.weekTotal ?? 0;
      return { credit: Math.min(1, weekTotal / target), expected: target, reconciled: true };
    }
  }
}

/** Mean credit over active habits; null when no habits are applicable. */
export function habitComponentRaw(credits: number[]): number | null {
  if (credits.length === 0) return null;
  return credits.reduce((a, c) => a + c, 0) / credits.length;
}

// ---------- feel ----------

/** Mood 0-100 → [0,1]; null (no entry) = not applicable. */
export function feelRaw(moodValue: number | null): number | null {
  if (moodValue === null) return null;
  return Math.min(100, Math.max(0, moodValue)) / 100;
}

// ---------- total ----------

export interface DailyScoreInput {
  weights: ScoreWeights;
  taskRaw: number | null;
  habitRaw: number | null;
  feelRaw: number | null;
}

export interface DailyScoreResult {
  total: number | null; // null = nothing applicable ("—", not 0)
  taskPoints: number | null;
  habitPoints: number | null;
  feelPoints: number | null;
  applicableWeight: number;
}

export function computeDailyScore(input: DailyScoreInput): DailyScoreResult {
  const components: { weight: number; raw: number }[] = [];

  const taskRaw = input.taskRaw;
  if (taskRaw !== null) components.push({ weight: input.weights.tasks, raw: taskRaw });
  if (input.habitRaw !== null) components.push({ weight: input.weights.habits, raw: input.habitRaw });
  if (input.feelRaw !== null) components.push({ weight: input.weights.feel, raw: input.feelRaw });

  const applicableWeight = components.reduce((a, c) => a + c.weight, 0);
  const round2 = (n: number) => Math.round(n * 100) / 100;

  return {
    total:
      applicableWeight === 0
        ? null
        : round2((100 * components.reduce((a, c) => a + c.weight * c.raw, 0)) / applicableWeight),
    taskPoints: taskRaw === null ? null : round2(input.weights.tasks * taskRaw),
    habitPoints: input.habitRaw === null ? null : round2(input.weights.habits * input.habitRaw),
    feelPoints: input.feelRaw === null ? null : round2(input.weights.feel * input.feelRaw),
    applicableWeight,
  };
}

// ---------- streaks ----------

export interface StreakResult {
  current: number;
  best: number;
}

/**
 * Daily/multi-daily streak: consecutive days at FULL completion (credit 1.0 —
 * partial days break it; the streak is the "hard" metric, the score is the
 * forgiving one). An incomplete *today* does not break the streak until the
 * day boundary passes: current counts back from today if today qualifies,
 * else from yesterday.
 */
export function dailyStreak(
  qualifyingDayKeys: ReadonlySet<string>,
  todayKey: string,
  addDaysFn: (dayKey: string, days: number) => string,
): StreakResult {
  const countBackFrom = (start: string): number => {
    let n = 0;
    let day = start;
    while (qualifyingDayKeys.has(day)) {
      n++;
      day = addDaysFn(day, -1);
    }
    return n;
  };

  const current = qualifyingDayKeys.has(todayKey)
    ? countBackFrom(todayKey)
    : countBackFrom(addDaysFn(todayKey, -1));

  // Best: scan all runs.
  let best = current;
  for (const day of qualifyingDayKeys) {
    if (qualifyingDayKeys.has(addDaysFn(day, 1))) continue; // not the end of a run
    best = Math.max(best, countBackFrom(day));
  }
  return { current, best };
}

/**
 * Weekly-habit streak: consecutive weeks hitting the target, counted in weeks.
 * The in-progress week neither extends nor breaks the streak — unless it has
 * already hit the target, in which case it extends immediately.
 */
export function weeklyStreak(
  qualifyingWeekStarts: ReadonlySet<string>,
  currentWeekStart: string,
  addDaysFn: (dayKey: string, days: number) => string,
): StreakResult {
  const countBackFrom = (start: string): number => {
    let n = 0;
    let week = start;
    while (qualifyingWeekStarts.has(week)) {
      n++;
      week = addDaysFn(week, -7);
    }
    return n;
  };

  const current = qualifyingWeekStarts.has(currentWeekStart)
    ? countBackFrom(currentWeekStart)
    : countBackFrom(addDaysFn(currentWeekStart, -7));

  let best = current;
  for (const week of qualifyingWeekStarts) {
    if (qualifyingWeekStarts.has(addDaysFn(week, 7))) continue;
    best = Math.max(best, countBackFrom(week));
  }
  return { current, best };
}

// ---------- pace display (UI status chip, not scoring) ----------

export type PaceStatus =
  | { kind: "week_done" }
  | { kind: "on_pace" }
  | { kind: "behind"; by: number }
  | { kind: "out_of_reach" };

/**
 * Friendlier display rule than the scoring formula: on-pace iff
 * done >= ceil(target × elapsedFullDays / 7), where today only counts as
 * elapsed from 18:00 — the app never calls you "behind" at 7 AM.
 */
export function paceStatus(args: {
  targetReps: number;
  weekTotal: number;
  elapsedDayOfWeek: number; // Mon=1 .. Sun=7 (today)
  hourOfDay: number; // 0-23, user-local
}): PaceStatus {
  const target = Math.max(1, args.targetReps);
  if (args.weekTotal >= target) return { kind: "week_done" };

  const remainingDays = 7 - args.elapsedDayOfWeek + (args.hourOfDay < 18 ? 1 : 0);
  if (target - args.weekTotal > remainingDays) return { kind: "out_of_reach" };

  const elapsedFullDays = args.hourOfDay >= 18 ? args.elapsedDayOfWeek : args.elapsedDayOfWeek - 1;
  const expected = Math.ceil((target * elapsedFullDays) / 7);
  if (args.weekTotal >= expected) return { kind: "on_pace" };
  return { kind: "behind", by: expected - args.weekTotal };
}

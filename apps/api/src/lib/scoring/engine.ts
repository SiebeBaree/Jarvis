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
   * true while the scored day's week is still running (live best-case credit);
   * false once the week has fully ended (uniform weekly-total reconciliation).
   */
  isLive: boolean;
}

export interface HabitCreditResult {
  credit: number; // 0..1
  /**
   * Reps needed by the end of the scored day (for the breakdown). For a live
   * weekly habit this is the minimum that keeps a perfect week reachable, so
   * it is 0 early in the week and rises to the full target by Sunday.
   */
  expected: number;
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
        // Live credit is the best value this day can still finalize at, not a
        // pace verdict: every day left in the week counts as a rep you can
        // still land. Missing Monday with six days to go costs nothing,
        // because reconciliation can still bring that Monday to a full 1.
        // Credit drops only once the shortfall is real (Thursday with 0 of 5
        // done can reach at most 4), and on Sunday it already equals the
        // reconciled value, so finalizing a played-out week moves nothing.
        const daysLeft = Math.max(0, 7 - (input.elapsedDayOfWeek ?? 7));
        const done = input.doneThroughDay ?? 0;
        // Reps that must be in the bag by tonight to keep a perfect week
        // reachable. Credit is 1 exactly when done >= expected.
        const expected = Math.max(0, target - daysLeft);
        return { credit: Math.min(1, (done + daysLeft) / target), expected, reconciled: false };
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

// ---------- pace display (UI status chip, not scoring) ----------

export type PaceStatus =
  | { kind: "week_done" }
  | { kind: "on_track"; remaining: number; daysLeft: number }
  | { kind: "last_chance"; remaining: number; daysLeft: number }
  | { kind: "out_of_reach"; remaining: number; daysLeft: number };

/**
 * The same reachability rule the scoring formula uses, so the chip and the
 * score never disagree. A weekly habit is only in trouble once the target
 * stops being reachable in the days that are left, which is why there is no
 * "behind" state: missing Tuesday on a 5x week leaves 4 to do in 5 days, and
 * that is on track, not a shortfall.
 *
 * Today always counts as a day you can still act on, so there is no hour rule.
 */
export function paceStatus(args: {
  targetReps: number;
  weekTotal: number;
  elapsedDayOfWeek: number; // Mon=1 .. Sun=7 (today)
}): PaceStatus {
  const target = Math.max(1, args.targetReps);
  const remaining = target - args.weekTotal;
  if (remaining <= 0) return { kind: "week_done" };

  const daysLeft = Math.max(0, 8 - args.elapsedDayOfWeek); // today included
  if (remaining > daysLeft) return { kind: "out_of_reach", remaining, daysLeft };
  if (remaining === daysLeft) return { kind: "last_chance", remaining, daysLeft };
  return { kind: "on_track", remaining, daysLeft };
}

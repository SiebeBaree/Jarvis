// Goal progress: the two numbers the Goals tab is built around.
//
//   timeProgress     — how much of the goal's window has burned.
//   progress         — how much of the goal is actually done.
//
// Both are fractions in [0,1] so the client can draw them as two bars of the
// same length and let the gap speak for itself. `progress` is null when the
// goal carries neither a numeric target nor milestones; a time bar on its own
// is still useful ("6 weeks left").

import { diffDays, type DayKey } from "./daykey";

export interface GoalLike {
  startDate: DayKey;
  targetDate: DayKey;
  startValue: number | null;
  targetValue: number | null;
  currentValue: number | null;
}

export interface MilestoneLike {
  goalId: string;
  doneAt: Date | null;
}

export type GoalTracking = "numeric" | "milestones" | "none";

export interface GoalProgress {
  tracking: GoalTracking;
  /** 0..1, or null when nothing measurable is attached. */
  progress: number | null;
  /** 0..1, clamped — a goal past its target date sits at 1, not 1.4. */
  timeProgress: number;
  daysTotal: number;
  /** Negative once the target date has passed. */
  daysRemaining: number;
  milestonesDone: number;
  milestonesTotal: number;
}

const clamp01 = (n: number): number => Math.min(1, Math.max(0, n));

/**
 * Numeric progress measured from the baseline, so a downward goal (92 → 80 kg)
 * and an upward one (0 → 10k) both read 0 at the start and 1 at the target.
 * Overshooting caps at 1; sliding backwards past the baseline floors at 0.
 */
function numericProgress(goal: GoalLike): number | null {
  const { startValue, targetValue, currentValue } = goal;
  if (startValue === null || targetValue === null) return null;
  if (startValue === targetValue) return null;
  const current = currentValue ?? startValue;
  return clamp01((current - startValue) / (targetValue - startValue));
}

export function goalProgress(goal: GoalLike, milestones: MilestoneLike[], today: DayKey): GoalProgress {
  const milestonesTotal = milestones.length;
  const milestonesDone = milestones.filter((m) => m.doneAt !== null).length;

  const numeric = numericProgress(goal);
  const tracking: GoalTracking =
    numeric !== null ? "numeric" : milestonesTotal > 0 ? "milestones" : "none";

  const progress =
    tracking === "numeric"
      ? numeric
      : tracking === "milestones"
        ? milestonesDone / milestonesTotal
        : null;

  // Inclusive of both endpoints: a one-day goal spans 1 day, not 0, so the
  // time bar can't divide by zero.
  const daysTotal = Math.max(1, diffDays(goal.startDate, goal.targetDate) + 1);
  const elapsed = diffDays(goal.startDate, today);

  return {
    tracking,
    progress,
    timeProgress: clamp01(elapsed / daysTotal),
    daysTotal,
    daysRemaining: diffDays(today, goal.targetDate),
    milestonesDone,
    milestonesTotal,
  };
}

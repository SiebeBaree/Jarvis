/**
 * Momentum scoring: a weighted completion score for a day's scheduled habits.
 * Pure and dependency-free.
 */

export type HabitWeight = 1 | 2 | 3;

export interface MomentumHabitInput {
  weight: HabitWeight;
  /** Credit already resolved to the range 0..1. */
  credit: number;
}

export interface MomentumResult {
  score: number;
  completedWeight: number;
  scheduledWeight: number;
}

/**
 * Computes the momentum score for a set of scheduled habits.
 *
 * `score = round(100 * Σ(credit * weight) / Σ(weight))`.
 * Returns `null` for empty input (a rest day with nothing scheduled).
 */
export function computeMomentum(
  habits: MomentumHabitInput[],
): MomentumResult | null {
  if (habits.length === 0) return null;

  let completedWeight = 0;
  let scheduledWeight = 0;
  for (const habit of habits) {
    const credit = clamp01(habit.credit);
    completedWeight += credit * habit.weight;
    scheduledWeight += habit.weight;
  }

  const score = Math.round((100 * completedWeight) / scheduledWeight);
  return { score, completedWeight, scheduledWeight };
}

/** Credit for a binary (done / not done) habit. */
export function creditForBinary(completed: boolean): number {
  return completed ? 1 : 0;
}

/**
 * Credit for a quantity habit: `min(logged / target, 1)`.
 * Guards `target <= 0` → 0, and clamps negative logged values to 0.
 */
export function creditForQuantity(logged: number, target: number): number {
  if (target <= 0) return 0;
  if (logged <= 0) return 0;
  return Math.min(logged / target, 1);
}

function clamp01(value: number): number {
  if (value <= 0) return 0;
  if (value >= 1) return 1;
  return value;
}

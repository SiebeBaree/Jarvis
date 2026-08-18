// Pure lifting arithmetic. Deliberately free of any database import so it can
// be unit-tested on its own — `lib/training.ts` re-exports these for routes.

export interface SetLike {
  weightKg: number | null;
  reps: number | null;
  isWarmup: boolean;
}

/**
 * Epley estimate. Used only to rank sets against each other ("is 100×5 better
 * than 90×8?"), never shown as a number the user is meant to trust as a true
 * one-rep max.
 */
export function estimateOneRepMax(weightKg: number | null, reps: number | null): number {
  if (weightKg == null || reps == null || reps <= 0) return 0;
  return weightKg * (1 + reps / 30);
}

/** Warm-ups are logged but never counted — they would flatter every total. */
export function volumeOf(sets: readonly Pick<SetLike, "weightKg" | "reps" | "isWarmup">[]): number {
  const total = sets.reduce((sum, set) => {
    if (set.isWarmup) return sum;
    return sum + (set.weightKg ?? 0) * (set.reps ?? 0);
  }, 0);
  return Math.round(total * 10) / 10;
}

export function workingSetCount(sets: readonly Pick<SetLike, "isWarmup">[]): number {
  return sets.filter((set) => !set.isWarmup).length;
}

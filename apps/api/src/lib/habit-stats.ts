// Helpers for GET /habits/:id/calendar and /habits/:id/stats.

import { and, eq, gte, lte, sql, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { habitCompletions } from "@/db/schema";
import type { SettingsRow } from "./auth";
import { addDays, weekEnd, weekStart, type DayKey } from "./daykey";
import { dailyStreak, weeklyStreak } from "./scoring/engine";
import { habitApplicable, type HabitRow } from "./scoring/snapshot";

export const round2 = (n: number): number => Math.round(n * 100) / 100;

/** reps per dayKey for one habit, optionally limited to [from, to]. */
export async function habitRepsByDay(
  userId: string,
  habitId: string,
  from?: DayKey,
  to?: DayKey,
): Promise<Map<DayKey, number>> {
  const conditions: SQL[] = [
    eq(habitCompletions.userId, userId),
    eq(habitCompletions.habitId, habitId),
  ];
  if (from) conditions.push(gte(habitCompletions.dayKey, from));
  if (to) conditions.push(lte(habitCompletions.dayKey, to));

  const rows = await db
    .select({ dayKey: habitCompletions.dayKey, reps: sql<number>`count(*)::int` })
    .from(habitCompletions)
    .where(and(...conditions))
    .groupBy(habitCompletions.dayKey);

  return new Map(rows.map((r) => [r.dayKey, r.reps]));
}

export interface HabitStats {
  type: HabitRow["type"];
  streak: { current: number; best: number; unit: "days" | "weeks" };
  rates: Record<string, number | null>;
  totalReps: number;
  firstLoggedDay: DayKey | null;
  currentWeek?: { total: number; target: number };
}

/** Pure stats computation from the habit's full completion history. */
export function buildHabitStats(
  habit: HabitRow,
  settings: SettingsRow,
  today: DayKey,
  repsByDay: Map<DayKey, number>,
): HabitStats {
  let totalReps = 0;
  let firstLoggedDay: DayKey | null = null;
  for (const [day, reps] of repsByDay) {
    totalReps += reps;
    if (firstLoggedDay === null || day < firstLoggedDay) firstLoggedDay = day;
  }

  if (habit.type === "weekly_frequency") {
    const weekTotals = new Map<DayKey, number>();
    for (const [day, reps] of repsByDay) {
      const ws = weekStart(day);
      weekTotals.set(ws, (weekTotals.get(ws) ?? 0) + reps);
    }
    const qualifying = new Set(
      [...weekTotals].filter(([, total]) => total >= habit.targetReps).map(([ws]) => ws),
    );
    const currentWeekStart = weekStart(today);
    const streak = weeklyStreak(qualifying, currentWeekStart, addDays);

    // Met weeks ÷ fully completed weeks in the last N weeks (capped at startDate).
    const rate = (nWeeks: number): number | null => {
      let counted = 0;
      let met = 0;
      for (let k = 1; k <= nWeeks; k++) {
        const ws = addDays(currentWeekStart, -7 * k);
        if (weekEnd(ws) < habit.startDate) break;
        counted++;
        if (qualifying.has(ws)) met++;
      }
      return counted === 0 ? null : round2(met / counted);
    };

    return {
      type: habit.type,
      streak: { ...streak, unit: "weeks" },
      rates: { last4Weeks: rate(4), last12Weeks: rate(12) },
      totalReps,
      firstLoggedDay,
      currentWeek: { total: weekTotals.get(currentWeekStart) ?? 0, target: habit.targetReps },
    };
  }

  // daily / multi_daily: a day qualifies at full completion.
  const qualifying = new Set(
    [...repsByDay].filter(([, reps]) => reps >= habit.targetReps).map(([day]) => day),
  );
  const streak = dailyStreak(qualifying, today, addDays);

  const rate = (windowDays: number): number | null => {
    let start = addDays(today, -(windowDays - 1));
    if (start < habit.startDate) start = habit.startDate;
    let applicable = 0;
    let met = 0;
    for (let day = start; day <= today; day = addDays(day, 1)) {
      if (!habitApplicable(habit, day, settings)) continue;
      applicable++;
      if (qualifying.has(day)) met++;
    }
    return applicable === 0 ? null : round2(met / applicable);
  };

  return {
    type: habit.type,
    streak: { ...streak, unit: "days" },
    rates: { last7: rate(7), last30: rate(30), last90: rate(90) },
    totalReps,
    firstLoggedDay,
  };
}

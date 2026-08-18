// Gathers the facts the nudge copy talks about.
//
// Everything here is read-only and scoped to one user and one dayKey. The
// queries are deliberately small: this runs from a cron on a schedule nobody is
// waiting on, but it still shares a database with the app.

import { and, eq, gte, inArray, isNull, ne, sql } from "drizzle-orm";
import { db } from "@/db/client";
import { habitCompletions, habits, moodEntries, tasks } from "@/db/schema";
import type { SettingsRow } from "../auth";
import { addDays, type DayKey } from "../daykey";
import { dailyStreak } from "../scoring/engine";
import { habitApplicable } from "../scoring/snapshot";
import type { CheckinNudgeData } from "./message";

/** How far back to look for streaks. Longer than any streak worth naming. */
const STREAK_WINDOW_DAYS = 400;

/** True when the user has already recorded how the day felt. */
export async function hasMoodFor(userId: string, dayKey: DayKey): Promise<boolean> {
  const [row] = await db
    .select({ dayKey: moodEntries.dayKey })
    .from(moodEntries)
    .where(and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, dayKey)))
    .limit(1);
  return row !== undefined;
}

export async function gatherNudgeData(
  userId: string,
  settings: SettingsRow,
  dayKey: DayKey,
): Promise<CheckinNudgeData> {
  const yesterday = addDays(dayKey, -1);

  const [yesterdayMoodRows, anyMoodRows, taskCounts] = await Promise.all([
    db
      .select({ value: moodEntries.value })
      .from(moodEntries)
      .where(and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, yesterday)))
      .limit(1),
    db
      .select({ dayKey: moodEntries.dayKey })
      .from(moodEntries)
      .where(eq(moodEntries.userId, userId))
      .limit(1),
    // Both counts in one pass over the (userId, dueDate, status) index.
    db
      .select({
        dueToday: sql<number>`count(*) filter (where ${tasks.dueDate} = ${dayKey})::int`,
        overdue: sql<number>`count(*) filter (where ${tasks.dueDate} < ${dayKey})::int`,
      })
      .from(tasks)
      .where(and(eq(tasks.userId, userId), eq(tasks.status, "open"))),
  ]);

  return {
    dayKey,
    yesterdayMood: yesterdayMoodRows[0]?.value ?? null,
    openTasksToday: taskCounts[0]?.dueToday ?? 0,
    overdueTasks: taskCounts[0]?.overdue ?? 0,
    bestActiveStreak: await bestActiveStreak(userId, settings, dayKey),
    hasAnyMoodEntry: anyMoodRows.length > 0,
  };
}

/**
 * The longest run currently going among the daily habits. Weekly habits are
 * left out: "4 weeks in a row" and "4 days in a row" in the same sentence slot
 * would read as the same thing and mean very different ones.
 */
async function bestActiveStreak(
  userId: string,
  settings: SettingsRow,
  dayKey: DayKey,
): Promise<{ habitName: string; days: number } | null> {
  const active = await db
    .select()
    .from(habits)
    .where(
      and(
        eq(habits.userId, userId),
        isNull(habits.archivedAt),
        isNull(habits.pausedAt),
        ne(habits.type, "weekly_frequency"),
      ),
    );
  if (active.length === 0) return null;

  const since = addDays(dayKey, -STREAK_WINDOW_DAYS);
  const reps = await db
    .select({
      habitId: habitCompletions.habitId,
      dayKey: habitCompletions.dayKey,
      reps: sql<number>`count(*)::int`,
    })
    .from(habitCompletions)
    .where(
      and(
        eq(habitCompletions.userId, userId),
        gte(habitCompletions.dayKey, since),
        inArray(
          habitCompletions.habitId,
          active.map((h) => h.id),
        ),
      ),
    )
    .groupBy(habitCompletions.habitId, habitCompletions.dayKey);

  const byHabit = new Map<string, Set<DayKey>>();
  for (const row of reps) {
    const habit = active.find((h) => h.id === row.habitId);
    if (!habit || row.reps < habit.targetReps) continue; // a partial day is not a streak day
    let days = byHabit.get(row.habitId);
    if (!days) {
      days = new Set();
      byHabit.set(row.habitId, days);
    }
    days.add(row.dayKey);
  }

  let best: { habitName: string; days: number } | null = null;
  for (const habit of active) {
    if (!habitApplicable(habit, dayKey, settings)) continue;
    const qualifying = byHabit.get(habit.id);
    if (!qualifying) continue;
    const { current } = dailyStreak(qualifying, dayKey, addDays);
    if (current > 0 && (best === null || current > best.days)) {
      best = { habitName: habit.name, days: current };
    }
  }
  return best;
}

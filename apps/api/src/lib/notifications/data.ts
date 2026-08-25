// Gathers the facts the nudge copy talks about.
//
// Everything here is read-only and scoped to one user and one dayKey. The
// queries are deliberately small: this runs from a cron on a schedule nobody is
// waiting on, but it still shares a database with the app.

import { and, eq, sql } from "drizzle-orm";
import { db } from "@/db/client";
import { moodEntries, tasks } from "@/db/schema";
import { addDays, type DayKey } from "../daykey";
import type { CheckinNudgeData } from "./message";

/** True when the user has already recorded how the day felt. */
export async function hasMoodFor(userId: string, dayKey: DayKey): Promise<boolean> {
  const [row] = await db
    .select({ dayKey: moodEntries.dayKey })
    .from(moodEntries)
    .where(and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, dayKey)))
    .limit(1);
  return row !== undefined;
}

export async function gatherNudgeData(userId: string, dayKey: DayKey): Promise<CheckinNudgeData> {
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
    hasAnyMoodEntry: anyMoodRows.length > 0,
  };
}

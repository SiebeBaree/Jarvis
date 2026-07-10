// Bridges the pure scoring engine to the database: builds inputs for a day,
// recomputes/upserts daily_scores rows, and lazily finalizes past days once
// their week has fully ended (weekly-habit reconciliation needs the whole week).

import { and, eq, gte, inArray, isNull, lte, sql } from "drizzle-orm";
import { db } from "@/db/client";
import {
  blocks,
  dailyScores,
  habits,
  habitCompletions,
  moodEntries,
  tasks,
  users,
  type ScoreBreakdown,
} from "@/db/schema";
import type { SettingsRow } from "../auth";
import {
  addDays,
  dayKeyFor,
  isReviewWeek as isReviewWeekFn,
  isoWeekday,
  weekEnd,
  weekStart,
  type DayKey,
} from "../daykey";
import {
  computeDailyScore,
  feelRaw,
  habitComponentRaw,
  habitCredit,
  taskComponent,
  type TaskForScoring,
} from "./engine";

export function todayKey(settings: SettingsRow, now = new Date()): DayKey {
  return dayKeyFor(now, settings.timezone, settings.dayBoundaryHour);
}

/** Hour of day (0-23) in the user's timezone — for the pace display rule. */
export function localHour(settings: SettingsRow, now = new Date()): number {
  return Number(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: settings.timezone,
      hour: "2-digit",
      hour12: false,
    }).format(now),
  );
}

export async function activeBlockFor(userId: string, dayKey: DayKey) {
  return db.query.blocks.findFirst({
    where: and(
      eq(blocks.userId, userId),
      eq(blocks.status, "active"),
      lte(blocks.startDate, dayKey),
      gte(blocks.endDate, dayKey),
    ),
  });
}

export type HabitRow = typeof habits.$inferSelect;

/** A habit counts on `dayKey` if it had started and wasn't archived/paused yet. */
export function habitApplicable(habit: HabitRow, dayKey: DayKey, settings: SettingsRow): boolean {
  if (habit.startDate > dayKey) return false;
  if (habit.archivedAt && dayKeyFor(habit.archivedAt, settings.timezone, settings.dayBoundaryHour) <= dayKey)
    return false;
  if (habit.pausedAt && dayKeyFor(habit.pausedAt, settings.timezone, settings.dayBoundaryHour) <= dayKey)
    return false;
  return true;
}

export async function applicableHabits(
  userId: string,
  dayKey: DayKey,
  settings: SettingsRow,
): Promise<HabitRow[]> {
  const all = await db.query.habits.findMany({ where: eq(habits.userId, userId) });
  return all.filter((h) => habitApplicable(h, dayKey, settings));
}

/** reps per (habitId, dayKey) within [from, to]. */
export async function repCounts(
  userId: string,
  from: DayKey,
  to: DayKey,
): Promise<Map<string, Map<DayKey, number>>> {
  const rows = await db
    .select({
      habitId: habitCompletions.habitId,
      dayKey: habitCompletions.dayKey,
      reps: sql<number>`count(*)::int`,
    })
    .from(habitCompletions)
    .where(
      and(
        eq(habitCompletions.userId, userId),
        gte(habitCompletions.dayKey, from),
        lte(habitCompletions.dayKey, to),
      ),
    )
    .groupBy(habitCompletions.habitId, habitCompletions.dayKey);

  const map = new Map<string, Map<DayKey, number>>();
  for (const row of rows) {
    let inner = map.get(row.habitId);
    if (!inner) map.set(row.habitId, (inner = new Map()));
    inner.set(row.dayKey, row.reps);
  }
  return map;
}

async function tasksForScoring(userId: string, dayKey: DayKey, settings: SettingsRow): Promise<TaskForScoring[]> {
  const topLevel = await db.query.tasks.findMany({
    where: and(eq(tasks.userId, userId), eq(tasks.dueDate, dayKey), isNull(tasks.parentTaskId)),
  });
  if (topLevel.length === 0) return [];
  const subtasks = await db.query.tasks.findMany({
    where: inArray(tasks.parentTaskId, topLevel.map((t) => t.id)),
  });
  const byParent = new Map<string, { status: "open" | "done" | "cancelled" }[]>();
  for (const s of subtasks) {
    const list = byParent.get(s.parentTaskId!) ?? [];
    list.push({ status: s.status });
    byParent.set(s.parentTaskId!, list);
  }
  return topLevel.map((t) => ({
    id: t.id,
    status: t.status,
    subtasks: byParent.get(t.id) ?? [],
    completedDayKey: t.completedAt
      ? dayKeyFor(t.completedAt, settings.timezone, settings.dayBoundaryHour)
      : null,
    dueDate: dayKey,
  }));
}

export interface DaySnapshot {
  dayKey: DayKey;
  total: number | null;
  taskPoints: number | null;
  habitPoints: number | null;
  feelPoints: number | null;
  applicableWeight: number;
  isReviewWeek: boolean;
  isFinal: boolean;
  breakdown: ScoreBreakdown;
}

/**
 * Recompute one day's score and upsert its daily_scores row.
 * A day is live (provisional) until its whole *week* has ended — weekly-habit
 * credit reconciles to the uniform weekly total only then.
 */
export async function recomputeDay(
  userId: string,
  settings: SettingsRow,
  dayKey: DayKey,
  now = new Date(),
): Promise<DaySnapshot> {
  const today = todayKey(settings, now);
  const isLive = weekEnd(dayKey) >= today;

  const block = await activeBlockFor(userId, dayKey);
  const reviewWeek = block ? isReviewWeekFn(dayKey, block.startDate, block.endDate) : false;

  const [dueTasks, dayHabits, reps, mood] = await Promise.all([
    reviewWeek ? Promise.resolve([]) : tasksForScoring(userId, dayKey, settings),
    applicableHabits(userId, dayKey, settings),
    repCounts(userId, weekStart(dayKey), weekEnd(dayKey)),
    db.query.moodEntries.findFirst({
      where: and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, dayKey)),
    }),
  ]);

  const taskResult = taskComponent(dueTasks);

  const habitBreakdown: ScoreBreakdown["habits"] = dayHabits.map((habit) => {
    const habitReps = reps.get(habit.id) ?? new Map<DayKey, number>();
    const repsToday = habitReps.get(dayKey) ?? 0;
    let doneThroughDay = 0;
    let weekTotal = 0;
    for (const [day, count] of habitReps) {
      weekTotal += count;
      if (day <= dayKey) doneThroughDay += count;
    }
    const result = habitCredit({
      type: habit.type,
      targetReps: habit.targetReps,
      repsToday,
      doneThroughDay,
      weekTotal,
      elapsedDayOfWeek: isoWeekday(dayKey),
      isLive,
    });
    return {
      habitId: habit.id,
      credit: result.credit,
      reps: habit.type === "weekly_frequency" ? weekTotal : repsToday,
      expected: result.expected,
      reconciled: result.reconciled,
    };
  });

  const score = computeDailyScore({
    weights: settings.scoreWeights,
    taskRaw: taskResult.raw,
    habitRaw: habitComponentRaw(habitBreakdown.map((h) => h.credit)),
    feelRaw: feelRaw(mood?.value ?? null),
    isReviewWeek: reviewWeek,
  });

  const breakdown: ScoreBreakdown = { tasks: taskResult.perTask, habits: habitBreakdown };
  const snapshot: DaySnapshot = {
    dayKey,
    ...score,
    isReviewWeek: reviewWeek,
    isFinal: !isLive,
    breakdown,
  };

  await db
    .insert(dailyScores)
    .values({
      userId,
      dayKey,
      total: score.total,
      taskPoints: score.taskPoints,
      habitPoints: score.habitPoints,
      feelPoints: score.feelPoints,
      applicableWeight: score.applicableWeight,
      isReviewWeek: reviewWeek,
      breakdown,
      isFinal: !isLive,
      computedAt: now,
    })
    .onConflictDoUpdate({
      target: [dailyScores.userId, dailyScores.dayKey],
      set: {
        total: score.total,
        taskPoints: score.taskPoints,
        habitPoints: score.habitPoints,
        feelPoints: score.feelPoints,
        applicableWeight: score.applicableWeight,
        isReviewWeek: reviewWeek,
        breakdown,
        isFinal: !isLive,
        computedAt: now,
      },
    });

  return snapshot;
}

// Lazy finalization: at most once per interval per lambda instance.
const lastFinalizeCheck = new Map<string, number>();
const FINALIZE_INTERVAL_MS = 10 * 60 * 1000;
const FINALIZE_LOOKBACK_DAYS = 45;

/**
 * Finalize every day in completed weeks that has no final snapshot yet —
 * including days the app was never opened (missed habits still score).
 */
export async function finalizeThrough(userId: string, settings: SettingsRow, now = new Date()): Promise<void> {
  const last = lastFinalizeCheck.get(userId);
  if (last && now.getTime() - last < FINALIZE_INTERVAL_MS) return;
  lastFinalizeCheck.set(userId, now.getTime());

  const today = todayKey(settings, now);
  const currentWeekStart = weekStart(today);
  const finalizeEnd = addDays(currentWeekStart, -1); // Sunday of the last completed week

  const user = await db.query.users.findFirst({ where: eq(users.id, userId) });
  if (!user) return;
  const accountStart = dayKeyFor(user.createdAt, settings.timezone, settings.dayBoundaryHour);
  const lookbackStart = addDays(today, -FINALIZE_LOOKBACK_DAYS);
  const from = accountStart > lookbackStart ? accountStart : lookbackStart;
  if (from > finalizeEnd) return;

  const existing = await db.query.dailyScores.findMany({
    where: and(
      eq(dailyScores.userId, userId),
      gte(dailyScores.dayKey, from),
      lte(dailyScores.dayKey, finalizeEnd),
      eq(dailyScores.isFinal, true),
    ),
    columns: { dayKey: true },
  });
  const finalized = new Set(existing.map((r) => r.dayKey));

  for (let day = from; day <= finalizeEnd; day = addDays(day, 1)) {
    if (!finalized.has(day)) await recomputeDay(userId, settings, day, now);
  }
}

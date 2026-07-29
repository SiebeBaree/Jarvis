// Assembles the one-shot Today payload (and historical day payloads).
// GET /days/today triggers recurrence materialization + a provisional score
// recompute, so opening the app is what keeps the world consistent.

import { and, asc, eq, inArray, isNull, lt, ne } from "drizzle-orm";
import { db } from "@/db/client";
import { habits, moodEntries, recurrenceTemplates, tasks } from "@/db/schema";
import type { SettingsRow } from "./auth";
import { addDays, dayKeyFor, weekEnd, weekStart, type DayKey } from "./daykey";
import { occurrencesToGenerate } from "./recurrence";
import { paceStatus, type PaceStatus, type TaskForScoring } from "./scoring/engine";
import {
  applicableHabits,
  finalizeThrough,
  localHour,
  recomputeDay,
  repCounts,
  todayKey,
  type DaySnapshot,
} from "./scoring/snapshot";

const MATERIALIZE_HORIZON_DAYS = 14;

/** Expand recurrence templates into concrete tasks up to today + horizon. */
export async function materializeTemplates(
  userId: string,
  settings: SettingsRow,
  now = new Date(),
): Promise<void> {
  const through = addDays(todayKey(settings, now), MATERIALIZE_HORIZON_DAYS);
  const templates = await db.query.recurrenceTemplates.findMany({
    where: and(eq(recurrenceTemplates.userId, userId), isNull(recurrenceTemplates.pausedAt)),
  });

  // One insert and one update for the whole batch — this runs on the Today
  // path, where every extra query is a round-trip the user waits on.
  const rows: (typeof tasks.$inferInsert)[] = [];
  const generatedIds: string[] = [];

  for (const template of templates) {
    if (template.lastGeneratedThrough && template.lastGeneratedThrough >= through) continue;
    generatedIds.push(template.id);
    for (const dayKey of occurrencesToGenerate({
      rule: template.rule,
      startDate: template.startDate,
      endDate: template.endDate,
      lastGeneratedThrough: template.lastGeneratedThrough,
      through,
    })) {
      rows.push({
        userId,
        title: template.title,
        notes: template.notes,
        priority: template.priority,
        categoryId: template.categoryId,
        dueDate: dayKey,
        dueTime: template.dueTime,
        templateId: template.id,
        templateDate: dayKey,
      });
    }
  }

  if (generatedIds.length === 0) return;
  if (rows.length > 0) await db.insert(tasks).values(rows).onConflictDoNothing();
  await db
    .update(recurrenceTemplates)
    .set({ lastGeneratedThrough: through })
    .where(inArray(recurrenceTemplates.id, generatedIds));
}

export type TaskRow = typeof tasks.$inferSelect;
export type TaskDTO = TaskRow & { subtasks: TaskRow[] };

/** Subtasks of every given parent, grouped by parent id — one query. */
async function subtasksByParent(topLevel: TaskRow[]): Promise<Map<string, TaskRow[]>> {
  const byParent = new Map<string, TaskRow[]>();
  if (topLevel.length === 0) return byParent;
  const children = await db.query.tasks.findMany({
    where: inArray(tasks.parentTaskId, topLevel.map((t) => t.id)),
    orderBy: [asc(tasks.sortOrder), asc(tasks.createdAt)],
  });
  for (const child of children) {
    const list = byParent.get(child.parentTaskId!) ?? [];
    list.push(child);
    byParent.set(child.parentTaskId!, list);
  }
  return byParent;
}

export async function withSubtasks(topLevel: TaskRow[]): Promise<TaskDTO[]> {
  const byParent = await subtasksByParent(topLevel);
  return topLevel.map((t) => ({ ...t, subtasks: byParent.get(t.id) ?? [] }));
}

/** Narrow a repCounts map to a sub-range without another query. */
function sliceReps(
  all: Map<string, Map<DayKey, number>>,
  from: DayKey,
  to: DayKey,
): Map<string, Map<DayKey, number>> {
  const out = new Map<string, Map<DayKey, number>>();
  for (const [habitId, days] of all) {
    const inner = new Map<DayKey, number>();
    for (const [day, count] of days) {
      if (day >= from && day <= to) inner.set(day, count);
    }
    if (inner.size > 0) out.set(habitId, inner);
  }
  return out;
}

export interface HabitTodayEntry {
  habit: typeof habits.$inferSelect;
  repsToday: number;
  doneThroughDay: number;
  weekTotal: number;
  credit: number;
  pace: PaceStatus | null; // weekly_frequency only
  plannedToday: boolean;
  /** Reps for the trailing 7 days (oldest first, ending on dayKey) — the
   * backfill strip in the habits list. Can span the previous week. */
  recentDays: { dayKey: DayKey; reps: number }[];
}

export interface DayPayload {
  dayKey: DayKey;
  score: DaySnapshot;
  tasksDue: TaskDTO[];
  /** Open tasks from earlier days. Empty on a historical day payload — a past
   * day's overdue list is noise, not something you can still act on. */
  overdueTasks: TaskDTO[];
  habits: HabitTodayEntry[];
  mood: { value: number; note: string | null } | null;
}

export async function buildDayPayload(
  userId: string,
  settings: SettingsRow,
  dayKey: DayKey,
  options: { isToday: boolean },
  now = new Date(),
): Promise<DayPayload> {
  if (options.isToday) {
    await materializeTemplates(userId, settings, now);
    await finalizeThrough(userId, settings, now);
  }

  // One rep query covering both windows (score week + trailing 7 days).
  const repsFrom = weekStart(dayKey) < addDays(dayKey, -6) ? weekStart(dayKey) : addDays(dayKey, -6);
  const repsTo = weekEnd(dayKey) > dayKey ? weekEnd(dayKey) : dayKey;

  const [dueTop, overdueTop, dayHabits, allReps, mood] = await Promise.all([
    db.query.tasks.findMany({
      where: and(eq(tasks.userId, userId), eq(tasks.dueDate, dayKey), isNull(tasks.parentTaskId)),
      orderBy: [asc(tasks.sortOrder), asc(tasks.createdAt)],
    }),
    options.isToday
      ? db.query.tasks.findMany({
          where: and(
            eq(tasks.userId, userId),
            eq(tasks.status, "open"),
            lt(tasks.dueDate, dayKey),
            isNull(tasks.parentTaskId),
            ne(tasks.status, "cancelled"),
          ),
          orderBy: [asc(tasks.dueDate)],
        })
      : Promise.resolve([]),
    applicableHabits(userId, dayKey, settings),
    repCounts(userId, repsFrom, repsTo),
    db.query.moodEntries.findFirst({
      where: and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, dayKey)),
    }),
  ]);

  const reps = sliceReps(allReps, weekStart(dayKey), weekEnd(dayKey));
  const recentReps = sliceReps(allReps, addDays(dayKey, -6), dayKey);

  // Subtasks for the due AND overdue lists in one query; the score reuses them.
  const childrenByParent = await subtasksByParent([...dueTop, ...overdueTop]);
  const attach = (rows: TaskRow[]): TaskDTO[] =>
    rows.map((t) => ({ ...t, subtasks: childrenByParent.get(t.id) ?? [] }));

  const dueForScoring: TaskForScoring[] = dueTop.map((t) => ({
    id: t.id,
    status: t.status,
    subtasks: (childrenByParent.get(t.id) ?? []).map((s) => ({ status: s.status })),
    completedDayKey: t.completedAt
      ? dayKeyFor(t.completedAt, settings.timezone, settings.dayBoundaryHour)
      : null,
    dueDate: dayKey,
  }));

  const snapshot = await recomputeDay(userId, settings, dayKey, now, {
    dayHabits,
    reps,
    mood,
    dueTasks: dueForScoring,
  });

  const hour = localHour(settings, now);
  const creditByHabit = new Map(snapshot.breakdown.habits.map((h) => [h.habitId, h.credit]));

  const recentWindow = Array.from({ length: 7 }, (_, i) => addDays(dayKey, i - 6));

  const habitEntries: HabitTodayEntry[] = dayHabits.map((habit) => {
    const habitReps = reps.get(habit.id) ?? new Map<string, number>();
    const habitRecent = recentReps.get(habit.id) ?? new Map<string, number>();
    const repsToday = habitReps.get(dayKey) ?? 0;
    let doneThroughDay = 0;
    let weekTotal = 0;
    for (const [day, count] of habitReps) {
      weekTotal += count;
      if (day <= dayKey) doneThroughDay += count;
    }
    const isoDay = ((): number => {
      const jsDay = new Date(`${dayKey}T00:00:00Z`).getUTCDay();
      return jsDay === 0 ? 7 : jsDay;
    })();
    return {
      habit,
      repsToday,
      doneThroughDay,
      weekTotal,
      credit: creditByHabit.get(habit.id) ?? 0,
      pace:
        habit.type === "weekly_frequency"
          ? paceStatus({
              targetReps: habit.targetReps,
              weekTotal,
              elapsedDayOfWeek: isoDay,
              hourOfDay: hour,
            })
          : null,
      plannedToday: habit.type !== "weekly_frequency" || habit.plannedDays.length === 0
        ? true
        : habit.plannedDays.includes(isoDay),
      recentDays: recentWindow.map((day) => ({ dayKey: day, reps: habitRecent.get(day) ?? 0 })),
    };
  });

  return {
    dayKey,
    score: snapshot,
    tasksDue: attach(dueTop),
    overdueTasks: attach(overdueTop),
    habits: habitEntries,
    mood: mood ? { value: mood.value, note: mood.note } : null,
  };
}

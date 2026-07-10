// Assembles the one-shot Today payload (and historical day payloads).
// GET /days/today triggers recurrence materialization + a provisional score
// recompute, so opening the app is what keeps the world consistent.

import { and, asc, eq, inArray, isNull, lt, ne } from "drizzle-orm";
import { db } from "@/db/client";
import { habits, moodEntries, recurrenceTemplates, tasks } from "@/db/schema";
import type { SettingsRow } from "./auth";
import { reconcileBlockStatuses } from "./blocks";
import { addDays, weekEnd, weekStart, weekIndexInBlock, type DayKey } from "./daykey";
import { occurrencesToGenerate } from "./recurrence";
import { paceStatus, type PaceStatus } from "./scoring/engine";
import {
  activeBlockFor,
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

  for (const template of templates) {
    if (template.lastGeneratedThrough && template.lastGeneratedThrough >= through) continue;
    const occurrences = occurrencesToGenerate({
      rule: template.rule,
      startDate: template.startDate,
      endDate: template.endDate,
      lastGeneratedThrough: template.lastGeneratedThrough,
      through,
    });
    if (occurrences.length > 0) {
      await db
        .insert(tasks)
        .values(
          occurrences.map((dayKey) => ({
            userId,
            title: template.title,
            notes: template.notes,
            priority: template.priority,
            goalId: template.goalId,
            dueDate: dayKey,
            dueTime: template.dueTime,
            templateId: template.id,
            templateDate: dayKey,
          })),
        )
        .onConflictDoNothing();
    }
    await db
      .update(recurrenceTemplates)
      .set({ lastGeneratedThrough: through })
      .where(eq(recurrenceTemplates.id, template.id));
  }
}

export type TaskRow = typeof tasks.$inferSelect;
export type TaskDTO = TaskRow & { subtasks: TaskRow[] };

export async function withSubtasks(topLevel: TaskRow[]): Promise<TaskDTO[]> {
  if (topLevel.length === 0) return [];
  const children = await db.query.tasks.findMany({
    where: inArray(tasks.parentTaskId, topLevel.map((t) => t.id)),
    orderBy: [asc(tasks.sortOrder), asc(tasks.createdAt)],
  });
  const byParent = new Map<string, TaskRow[]>();
  for (const child of children) {
    const list = byParent.get(child.parentTaskId!) ?? [];
    list.push(child);
    byParent.set(child.parentTaskId!, list);
  }
  return topLevel.map((t) => ({ ...t, subtasks: byParent.get(t.id) ?? [] }));
}

export interface HabitTodayEntry {
  habit: typeof habits.$inferSelect;
  repsToday: number;
  doneThroughDay: number;
  weekTotal: number;
  credit: number;
  pace: PaceStatus | null; // weekly_frequency only
  plannedToday: boolean;
}

export interface DayPayload {
  dayKey: DayKey;
  weekNumber: number | null;
  isReviewWeek: boolean;
  block: { id: string; number: number; title: string; startDate: string; endDate: string } | null;
  score: DaySnapshot;
  tasksDue: TaskDTO[];
  overdueTasks: TaskDTO[];
  habits: HabitTodayEntry[];
  mood: { value: number; note: string | null } | null;
  /** Today only: yesterday has no mood entry yet (backfill row in the UI). */
  yesterdayMoodMissing: boolean;
  /**
   * Review week only: top-level non-cancelled tasks due this day that are
   * hidden by the week-13 task pause ("tasks are paused" copy). 0 otherwise.
   */
  pausedTaskCount: number;
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
    await reconcileBlockStatuses(userId, dayKey);
    await finalizeThrough(userId, settings, now);
  }

  const snapshot = await recomputeDay(userId, settings, dayKey, now);
  const block = await activeBlockFor(userId, dayKey);

  const [dueTop, overdueTop, dayHabits, reps, mood, yesterdayMood] = await Promise.all([
    db.query.tasks.findMany({
      where: and(eq(tasks.userId, userId), eq(tasks.dueDate, dayKey), isNull(tasks.parentTaskId)),
      orderBy: [asc(tasks.sortOrder), asc(tasks.createdAt)],
    }),
    // Review week pauses tasks: no overdue nagging during week 13.
    !snapshot.isReviewWeek
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
    repCounts(userId, weekStart(dayKey), weekEnd(dayKey)),
    db.query.moodEntries.findFirst({
      where: and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, dayKey)),
    }),
    options.isToday
      ? db.query.moodEntries.findFirst({
          where: and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, addDays(dayKey, -1))),
        })
      : Promise.resolve(undefined),
  ]);

  // Week 13 hides due tasks except templates that opted into "Scheduled anyway".
  let visibleDue = dueTop;
  let pausedTaskCount = 0;
  if (snapshot.isReviewWeek) {
    const templateIds = [
      ...new Set(dueTop.map((t) => t.templateId).filter((id): id is string => id !== null)),
    ];
    const shownTemplates =
      templateIds.length === 0
        ? []
        : await db.query.recurrenceTemplates.findMany({
            where: and(
              inArray(recurrenceTemplates.id, templateIds),
              eq(recurrenceTemplates.showInReviewWeek, true),
            ),
            columns: { id: true },
          });
    const shown = new Set(shownTemplates.map((t) => t.id));
    visibleDue = dueTop.filter((t) => t.templateId !== null && shown.has(t.templateId));
    const visibleIds = new Set(visibleDue.map((t) => t.id));
    pausedTaskCount = dueTop.filter(
      (t) => t.status !== "cancelled" && !visibleIds.has(t.id),
    ).length;
  }

  const hour = localHour(settings, now);
  const creditByHabit = new Map(snapshot.breakdown.habits.map((h) => [h.habitId, h.credit]));

  const habitEntries: HabitTodayEntry[] = dayHabits.map((habit) => {
    const habitReps = reps.get(habit.id) ?? new Map<string, number>();
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
    };
  });

  return {
    dayKey,
    weekNumber: block ? weekIndexInBlock(dayKey, block.startDate) : null,
    isReviewWeek: snapshot.isReviewWeek,
    block: block
      ? {
          id: block.id,
          number: block.number,
          title: block.title,
          startDate: block.startDate,
          endDate: block.endDate,
        }
      : null,
    score: snapshot,
    tasksDue: await withSubtasks(visibleDue),
    overdueTasks: await withSubtasks(overdueTop),
    habits: habitEntries,
    mood: mood ? { value: mood.value, note: mood.note } : null,
    yesterdayMoodMissing: options.isToday && !yesterdayMood,
    pausedTaskCount,
  };
}

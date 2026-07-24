// Assembles the one-shot Today payload (and historical day payloads).
// GET /days/today triggers recurrence materialization + a provisional score
// recompute, so opening the app is what keeps the world consistent.

import { and, asc, eq, gt, inArray, isNull, lt, ne } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks, habits, moodEntries, recurrenceTemplates, tasks } from "@/db/schema";
import type { SettingsRow } from "./auth";
import { reconcileBlockStatuses } from "./blocks";
import {
  addDays,
  dayKeyFor,
  isReviewWeek as isReviewWeekFn,
  weekEnd,
  weekStart,
  weekIndexInBlock,
  type DayKey,
} from "./daykey";
import { occurrencesToGenerate } from "./recurrence";
import { paceStatus, type PaceStatus, type TaskForScoring } from "./scoring/engine";
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
        goalId: template.goalId,
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
  weekNumber: number | null;
  isReviewWeek: boolean;
  block: { id: string; number: number; title: string; startDate: string; endDate: string } | null;
  /** Set when no block covers this day but one is scheduled to start later —
   * the client shows "starts Monday" instead of the plan-setup banner. */
  upcomingBlock: { id: string; number: number; title: string; startDate: string; endDate: string } | null;
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
    // Independent bookkeeping — no reason to pay for them one after another.
    await Promise.all([
      materializeTemplates(userId, settings, now),
      reconcileBlockStatuses(userId, dayKey),
    ]);
    await finalizeThrough(userId, settings, now);
  }

  // The block decides review-week behaviour, so it has to land before the
  // rest. Everything after it goes out in a single parallel batch, and the
  // score is computed from those same rows instead of re-reading them.
  const block = await activeBlockFor(userId, dayKey);
  const isReviewWeek = block ? isReviewWeekFn(dayKey, block.startDate, block.endDate) : false;

  // One rep query covering both windows (score week + trailing 7 days).
  const repsFrom = weekStart(dayKey) < addDays(dayKey, -6) ? weekStart(dayKey) : addDays(dayKey, -6);
  const repsTo = weekEnd(dayKey) > dayKey ? weekEnd(dayKey) : dayKey;

  const [dueTop, overdueTop, dayHabits, allReps, mood, yesterdayMood, upcoming] = await Promise.all([
    db.query.tasks.findMany({
      where: and(eq(tasks.userId, userId), eq(tasks.dueDate, dayKey), isNull(tasks.parentTaskId)),
      orderBy: [asc(tasks.sortOrder), asc(tasks.createdAt)],
    }),
    // Review week pauses tasks: no overdue nagging during week 13.
    !isReviewWeek
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
    options.isToday
      ? db.query.moodEntries.findFirst({
          where: and(eq(moodEntries.userId, userId), eq(moodEntries.dayKey, addDays(dayKey, -1))),
        })
      : Promise.resolve(undefined),
    block
      ? Promise.resolve(undefined)
      : db.query.blocks.findFirst({
          where: and(
            eq(blocks.userId, userId),
            gt(blocks.startDate, dayKey),
            ne(blocks.status, "completed"),
          ),
          orderBy: [asc(blocks.startDate)],
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
    block,
    dayHabits,
    reps,
    mood,
    dueTasks: dueForScoring,
  });

  // Week 13 hides due tasks except templates that opted into "Scheduled anyway".
  let visibleDue = dueTop;
  let pausedTaskCount = 0;
  if (isReviewWeek) {
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
    weekNumber: block ? weekIndexInBlock(dayKey, block.startDate) : null,
    isReviewWeek,
    block: block
      ? {
          id: block.id,
          number: block.number,
          title: block.title,
          startDate: block.startDate,
          endDate: block.endDate,
        }
      : null,
    upcomingBlock: upcoming
      ? {
          id: upcoming.id,
          number: upcoming.number,
          title: upcoming.title,
          startDate: upcoming.startDate,
          endDate: upcoming.endDate,
        }
      : null,
    score: snapshot,
    tasksDue: attach(visibleDue),
    overdueTasks: attach(overdueTop),
    habits: habitEntries,
    mood: mood ? { value: mood.value, note: mood.note } : null,
    yesterdayMoodMissing: options.isToday && !yesterdayMood,
    pausedTaskCount,
  };
}

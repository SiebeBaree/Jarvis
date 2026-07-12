// Chat-agent tool registry. Read tools execute inline during the agent loop;
// mutating tools NEVER execute from the loop — they become proposed_actions
// cards the user confirms, and confirmation executes the stored args here.
//
// Strict-schema note: OpenAI strict mode requires every field to be required,
// so args use .nullable() instead of .optional(); executors treat null as absent.

import { and, asc, desc, eq, gte, lte, sql } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/db/client";
import {
  goals,
  habitCompletions,
  habits,
  metricEntries,
  metricTypes,
  moodEntries,
  tasks,
  vision,
} from "@/db/schema";
import type { SettingsRow } from "../auth";
import { addDays, isValidDayKey, weekStart } from "../daykey";
import { buildHabitStats, habitRepsByDay } from "../habit-stats";
import { ApiError } from "../http";
import { recomputeDay, todayKey } from "../scoring/snapshot";
import { setTaskCompletion } from "../task-status";
import { buildDayPayload } from "../today";

export interface ToolContext {
  userId: string;
  settings: SettingsRow;
  /** Kind of the conversation the tool runs in ("chat" | "seeding" | reviews). */
  conversationKind?: string;
}

const dayKeyArg = z.string().refine(isValidDayKey, { message: "must be YYYY-MM-DD" });
const priorityArg = z.enum(["low", "medium", "high"]);

// ---------- read tools ----------

const READ_TOOLS = {
  get_today_summary: {
    description: "Full snapshot of today: score, tasks due, overdue, habits with pace, mood.",
    args: z.strictObject({}),
    execute: async (ctx: ToolContext) =>
      compactDay(await buildDayPayload(ctx.userId, ctx.settings, todayKey(ctx.settings), { isToday: false })),
  },
  get_day: {
    description: "Historical day snapshot (score breakdown, tasks, habits) for a past dayKey.",
    args: z.strictObject({ dayKey: dayKeyArg }),
    execute: async (ctx: ToolContext, args: { dayKey: string }) =>
      compactDay(await buildDayPayload(ctx.userId, ctx.settings, args.dayKey, { isToday: false })),
  },
  get_score_trends: {
    description: "Daily score totals for the last N days (7, 30, or 90).",
    args: z.strictObject({ days: z.union([z.literal(7), z.literal(30), z.literal(90)]) }),
    execute: async (ctx: ToolContext, args: { days: number }) => {
      const today = todayKey(ctx.settings);
      const { dailyScores } = await import("@/db/schema");
      const rows = await db.query.dailyScores.findMany({
        where: and(
          eq(dailyScores.userId, ctx.userId),
          gte(dailyScores.dayKey, addDays(today, -(args.days - 1))),
          lte(dailyScores.dayKey, today),
        ),
        orderBy: [asc(dailyScores.dayKey)],
      });
      return rows.map((r) => ({ dayKey: r.dayKey, total: r.total }));
    },
  },
  list_tasks: {
    description: "List tasks. view: today|upcoming|inbox|done|overdue.",
    args: z.strictObject({ view: z.enum(["today", "upcoming", "inbox", "done", "overdue"]) }),
    execute: async (ctx: ToolContext, args: { view: string }) => {
      const today = todayKey(ctx.settings);
      const base = [eq(tasks.userId, ctx.userId)];
      const rows = await db.query.tasks.findMany({
        where: and(...base),
        orderBy: [asc(tasks.dueDate)],
        limit: 300,
      });
      const top = rows.filter((t) => !t.parentTaskId);
      const byView = {
        today: top.filter((t) => t.dueDate === today && t.status !== "cancelled"),
        upcoming: top.filter((t) => t.dueDate !== null && t.dueDate > today && t.status === "open"),
        inbox: top.filter((t) => t.dueDate === null && t.status === "open"),
        done: top.filter((t) => t.status === "done").slice(-50),
        overdue: top.filter((t) => t.dueDate !== null && t.dueDate < today && t.status === "open"),
      }[args.view]!;
      return byView.map((t) => ({
        id: t.id,
        title: t.title,
        dueDate: t.dueDate,
        priority: t.priority,
        status: t.status,
        goalId: t.goalId,
      }));
    },
  },
  list_habits: {
    description: "All active habits with type, target, and planned days.",
    args: z.strictObject({}),
    execute: async (ctx: ToolContext) => {
      const rows = await db.query.habits.findMany({
        where: eq(habits.userId, ctx.userId),
        orderBy: [asc(habits.sortOrder)],
      });
      return rows
        .filter((h) => !h.archivedAt)
        .map((h) => ({
          id: h.id,
          name: h.name,
          type: h.type,
          targetReps: h.targetReps,
          plannedDays: h.plannedDays,
          paused: !!h.pausedAt,
          goalId: h.goalId,
        }));
    },
  },
  list_goals: {
    description: "All goals (optionally only the active block's).",
    args: z.strictObject({ activeBlockOnly: z.boolean() }),
    execute: async (ctx: ToolContext, args: { activeBlockOnly: boolean }) => {
      const rows = await db.query.goals.findMany({
        where: eq(goals.userId, ctx.userId),
        orderBy: [asc(goals.sortOrder)],
      });
      const { activeBlockFor } = await import("../scoring/snapshot");
      const block = args.activeBlockOnly
        ? await activeBlockFor(ctx.userId, todayKey(ctx.settings))
        : null;
      return rows
        .filter((g) => (block ? g.blockId === block.id : true))
        .map((g) => ({
          id: g.id,
          title: g.title,
          status: g.status,
          trackStatus: g.trackStatus,
          manualProgress: g.manualProgress,
          blockId: g.blockId,
        }));
    },
  },
  get_habit_stats: {
    description: "Streaks and completion rates for one habit.",
    args: z.strictObject({ habitId: z.string().uuid() }),
    execute: async (ctx: ToolContext, args: { habitId: string }) => {
      const habit = await db.query.habits.findFirst({
        where: and(eq(habits.id, args.habitId), eq(habits.userId, ctx.userId)),
      });
      if (!habit) throw new ApiError(404, "not_found", "Habit not found");
      const reps = await habitRepsByDay(ctx.userId, habit.id);
      return buildHabitStats(habit, ctx.settings, todayKey(ctx.settings), reps);
    },
  },
  get_mood: {
    description: "Mood entries between two dayKeys.",
    args: z.strictObject({ from: dayKeyArg, to: dayKeyArg }),
    execute: async (ctx: ToolContext, args: { from: string; to: string }) => {
      const rows = await db.query.moodEntries.findMany({
        where: and(
          eq(moodEntries.userId, ctx.userId),
          gte(moodEntries.dayKey, args.from),
          lte(moodEntries.dayKey, args.to),
        ),
        orderBy: [asc(moodEntries.dayKey)],
      });
      return rows.map((m) => ({ dayKey: m.dayKey, value: m.value, note: m.note }));
    },
  },
  get_improvement_areas: {
    description:
      "Self-improvement areas (posture, clothing, ...) with weekly photo check-in status and the latest AI commentary.",
    args: z.strictObject({}),
    execute: async (ctx: ToolContext) => {
      const { improvementAreas, areaCheckins } = await import("@/db/schema");
      const { weekStart } = await import("../daykey");
      const thisWeek = weekStart(todayKey(ctx.settings));
      const rows = await db.query.improvementAreas.findMany({
        where: eq(improvementAreas.userId, ctx.userId),
        orderBy: [asc(improvementAreas.sortOrder)],
      });
      const result = [];
      for (const area of rows.filter((a) => !a.archivedAt)) {
        const latest = await db.query.areaCheckins.findFirst({
          where: eq(areaCheckins.areaId, area.id),
          orderBy: [desc(areaCheckins.weekKey)],
        });
        result.push({
          id: area.id,
          name: area.name,
          betterLooksLike: area.betterLooksLike,
          dueThisWeek: !latest || latest.weekKey < thisWeek,
          lastCheckin: latest
            ? { weekKey: latest.weekKey, commentary: latest.aiCommentary?.slice(0, 400) ?? null }
            : null,
        });
      }
      return result;
    },
  },
  get_metrics: {
    description: "Body-metric types and their recent entries (weight, body fat, ...).",
    args: z.strictObject({}),
    execute: async (ctx: ToolContext) => {
      const types = await db.query.metricTypes.findMany({
        where: eq(metricTypes.userId, ctx.userId),
      });
      const result = [];
      for (const type of types.filter((t) => !t.archivedAt)) {
        const entries = await db.query.metricEntries.findMany({
          where: eq(metricEntries.metricTypeId, type.id),
          orderBy: [desc(metricEntries.dayKey)],
          limit: 10,
        });
        result.push({
          id: type.id,
          name: type.name,
          unit: type.unit,
          entries: entries.map((e) => ({ dayKey: e.dayKey, value: e.value })),
        });
      }
      return result;
    },
  },
} as const;

function compactDay(payload: Awaited<ReturnType<typeof buildDayPayload>>) {
  return {
    dayKey: payload.dayKey,
    weekNumber: payload.weekNumber,
    isReviewWeek: payload.isReviewWeek,
    score: {
      total: payload.score.total,
      taskPoints: payload.score.taskPoints,
      habitPoints: payload.score.habitPoints,
      feelPoints: payload.score.feelPoints,
    },
    mood: payload.mood,
    tasksDue: payload.tasksDue.map((t) => ({ id: t.id, title: t.title, status: t.status, priority: t.priority })),
    overdue: payload.overdueTasks.map((t) => ({ id: t.id, title: t.title, dueDate: t.dueDate })),
    habits: payload.habits.map((h) => ({
      id: h.habit.id,
      name: h.habit.name,
      type: h.habit.type,
      repsToday: h.repsToday,
      weekTotal: h.weekTotal,
      target: h.habit.targetReps,
      pace: h.pace?.kind ?? null,
    })),
  };
}

// ---------- mutating tools ----------

interface MutatingTool<A> {
  description: string;
  args: z.ZodType<A>;
  /** Human card text, generated from args by template — never by the model. */
  summarize: (args: A, ctx: ToolContext) => Promise<string> | string;
  execute: (ctx: ToolContext, args: A) => Promise<unknown>;
}

function mutating<A>(tool: MutatingTool<A>): MutatingTool<A> {
  return tool;
}

async function recomputeFor(ctx: ToolContext, dayKey: string | null | undefined) {
  await recomputeDay(ctx.userId, ctx.settings, dayKey ?? todayKey(ctx.settings));
}

const MUTATING_TOOLS = {
  create_task: mutating({
    description: "Create a one-off task. dueDate null = inbox.",
    args: z.strictObject({
      title: z.string().min(1).max(300),
      notes: z.string().max(5000).nullable(),
      dueDate: dayKeyArg.nullable(),
      priority: priorityArg.nullable(),
      goalId: z.string().uuid().nullable(),
    }),
    summarize: (a) =>
      `Create task "${a.title}"${a.dueDate ? ` · due ${a.dueDate}` : " · inbox"}${a.priority ? ` · ${a.priority}` : ""}`,
    execute: async (ctx, a) => {
      const [row] = await db
        .insert(tasks)
        .values({
          userId: ctx.userId,
          title: a.title,
          notes: a.notes,
          dueDate: a.dueDate,
          priority: a.priority ?? "medium",
          goalId: a.goalId,
        })
        .returning();
      await recomputeFor(ctx, a.dueDate);
      return { taskId: row!.id };
    },
  }),
  update_task: mutating({
    description: "Update a task's title, due date, priority, or goal link.",
    args: z.strictObject({
      taskId: z.string().uuid(),
      title: z.string().min(1).max(300).nullable(),
      dueDate: dayKeyArg.nullable(),
      clearDueDate: z.boolean(),
      priority: priorityArg.nullable(),
      goalId: z.string().uuid().nullable(),
    }),
    summarize: async (a, ctx) => {
      const existing = await db.query.tasks.findFirst({
        where: and(eq(tasks.id, a.taskId), eq(tasks.userId, ctx.userId)),
      });
      const changes = [
        a.title ? `title → "${a.title}"` : null,
        a.clearDueDate ? "due → none" : a.dueDate ? `due → ${a.dueDate}` : null,
        a.priority ? `priority → ${a.priority}` : null,
      ].filter(Boolean);
      return `Edit task "${existing?.title ?? a.taskId}": ${changes.join(", ") || "link change"}`;
    },
    execute: async (ctx, a) => {
      const existing = await db.query.tasks.findFirst({
        where: and(eq(tasks.id, a.taskId), eq(tasks.userId, ctx.userId)),
      });
      if (!existing) throw new ApiError(404, "not_found", "Task not found");
      const [row] = await db
        .update(tasks)
        .set({
          ...(a.title ? { title: a.title } : {}),
          ...(a.clearDueDate ? { dueDate: null } : a.dueDate ? { dueDate: a.dueDate } : {}),
          ...(a.priority ? { priority: a.priority } : {}),
          ...(a.goalId !== null ? { goalId: a.goalId } : {}),
          updatedAt: new Date(),
        })
        .where(eq(tasks.id, a.taskId))
        .returning();
      await recomputeFor(ctx, existing.dueDate);
      await recomputeFor(ctx, row!.dueDate);
      return { taskId: a.taskId };
    },
  }),
  complete_task: mutating({
    description: "Mark a task done.",
    args: z.strictObject({ taskId: z.string().uuid() }),
    summarize: async (a, ctx) => {
      const t = await db.query.tasks.findFirst({
        where: and(eq(tasks.id, a.taskId), eq(tasks.userId, ctx.userId)),
      });
      return `Complete task "${t?.title ?? a.taskId}"`;
    },
    execute: async (ctx, a) =>
      setTaskCompletion({ userId: ctx.userId, settings: ctx.settings, email: "", rawToken: "" }, a.taskId, true),
  }),
  delete_task: mutating({
    description: "Delete a task permanently.",
    args: z.strictObject({ taskId: z.string().uuid() }),
    summarize: async (a, ctx) => {
      const t = await db.query.tasks.findFirst({
        where: and(eq(tasks.id, a.taskId), eq(tasks.userId, ctx.userId)),
      });
      return `Delete task "${t?.title ?? a.taskId}"`;
    },
    execute: async (ctx, a) => {
      const existing = await db.query.tasks.findFirst({
        where: and(eq(tasks.id, a.taskId), eq(tasks.userId, ctx.userId)),
      });
      if (!existing) throw new ApiError(404, "not_found", "Task not found");
      await db.delete(tasks).where(eq(tasks.id, a.taskId));
      await recomputeFor(ctx, existing.dueDate);
      return { deleted: true };
    },
  }),
  create_habit: mutating({
    description:
      "Create a habit. type daily (1/day), multi_daily (targetReps/day), weekly_frequency (targetReps/week, plannedDays are soft suggestions).",
    args: z.strictObject({
      name: z.string().min(1).max(120),
      type: z.enum(["daily", "multi_daily", "weekly_frequency"]),
      targetReps: z.number().int().min(1).max(10).nullable(),
      plannedDays: z.array(z.number().int().min(1).max(7)).nullable(),
      icon: z.string().max(80).nullable(),
      goalId: z.string().uuid().nullable(),
    }),
    summarize: (a) => {
      const cadence =
        a.type === "daily" ? "daily" : a.type === "multi_daily" ? `${a.targetReps ?? 2}×/day` : `${a.targetReps ?? 3}×/week`;
      return `Create habit "${a.name}" · ${cadence}`;
    },
    execute: async (ctx, a) => {
      const target = a.type === "daily" ? 1 : (a.targetReps ?? (a.type === "multi_daily" ? 2 : 3));
      const [row] = await db
        .insert(habits)
        .values({
          userId: ctx.userId,
          name: a.name,
          type: a.type,
          targetReps: target,
          plannedDays: a.type === "weekly_frequency" ? (a.plannedDays ?? []) : [],
          icon: a.icon,
          goalId: a.goalId,
          startDate: todayKey(ctx.settings),
        })
        .returning();
      await recomputeFor(ctx, null);
      return { habitId: row!.id };
    },
  }),
  update_habit: mutating({
    description: "Update a habit's name, target, or planned days.",
    args: z.strictObject({
      habitId: z.string().uuid(),
      name: z.string().min(1).max(120).nullable(),
      targetReps: z.number().int().min(1).max(10).nullable(),
      plannedDays: z.array(z.number().int().min(1).max(7)).nullable(),
    }),
    summarize: async (a, ctx) => {
      const h = await db.query.habits.findFirst({
        where: and(eq(habits.id, a.habitId), eq(habits.userId, ctx.userId)),
      });
      const changes = [
        a.name ? `name → "${a.name}"` : null,
        a.targetReps ? `target → ${a.targetReps}` : null,
        a.plannedDays ? `planned days → ${a.plannedDays.join(",")}` : null,
      ].filter(Boolean);
      return `Edit habit "${h?.name ?? a.habitId}": ${changes.join(", ")}`;
    },
    execute: async (ctx, a) => {
      const existing = await db.query.habits.findFirst({
        where: and(eq(habits.id, a.habitId), eq(habits.userId, ctx.userId)),
      });
      if (!existing) throw new ApiError(404, "not_found", "Habit not found");
      await db
        .update(habits)
        .set({
          ...(a.name ? { name: a.name } : {}),
          ...(a.targetReps ? { targetReps: a.targetReps } : {}),
          ...(a.plannedDays ? { plannedDays: a.plannedDays } : {}),
        })
        .where(eq(habits.id, a.habitId));
      await recomputeFor(ctx, null);
      return { habitId: a.habitId };
    },
  }),
  archive_habit: mutating({
    description: "Archive a habit (stops counting from today; history kept).",
    args: z.strictObject({ habitId: z.string().uuid() }),
    summarize: async (a, ctx) => {
      const h = await db.query.habits.findFirst({
        where: and(eq(habits.id, a.habitId), eq(habits.userId, ctx.userId)),
      });
      return `Archive habit "${h?.name ?? a.habitId}"`;
    },
    execute: async (ctx, a) => {
      await db
        .update(habits)
        .set({ archivedAt: new Date() })
        .where(and(eq(habits.id, a.habitId), eq(habits.userId, ctx.userId)));
      await recomputeFor(ctx, null);
      return { archived: true };
    },
  }),
  log_habit: mutating({
    description: "Log one habit rep for today (or a past dayKey).",
    args: z.strictObject({ habitId: z.string().uuid(), dayKey: dayKeyArg.nullable() }),
    summarize: async (a, ctx) => {
      const h = await db.query.habits.findFirst({
        where: and(eq(habits.id, a.habitId), eq(habits.userId, ctx.userId)),
      });
      return `Log "${h?.name ?? a.habitId}"${a.dayKey ? ` for ${a.dayKey}` : " for today"}`;
    },
    execute: async (ctx, a) => {
      const habit = await db.query.habits.findFirst({
        where: and(eq(habits.id, a.habitId), eq(habits.userId, ctx.userId)),
      });
      if (!habit) throw new ApiError(404, "not_found", "Habit not found");
      const dayKey = a.dayKey ?? todayKey(ctx.settings);
      if (dayKey > todayKey(ctx.settings)) throw new ApiError(400, "future_day", "Cannot log the future");
      if (dayKey < habit.startDate) {
        throw new ApiError(400, "before_start", "Cannot log before the habit's start date");
      }
      // Same guards as POST /habits/:id/log — never overshoot the daily target.
      const [row] = await db
        .select({ n: sql<number>`count(*)::int` })
        .from(habitCompletions)
        .where(
          and(
            eq(habitCompletions.userId, ctx.userId),
            eq(habitCompletions.habitId, habit.id),
            eq(habitCompletions.dayKey, dayKey),
          ),
        );
      const reps = row?.n ?? 0;
      if (habit.type === "daily" && reps >= 1) {
        throw new ApiError(409, "already_logged", "Habit already logged for that day");
      }
      if (habit.type === "multi_daily" && reps >= habit.targetReps) {
        throw new ApiError(409, "target_reached", "Daily target already reached");
      }
      await db.insert(habitCompletions).values({ userId: ctx.userId, habitId: habit.id, dayKey });
      await recomputeFor(ctx, dayKey);
      return { logged: true, dayKey };
    },
  }),
  set_mood: mutating({
    description: "Set the mood value (0-100) for today or a past day.",
    args: z.strictObject({
      value: z.number().int().min(0).max(100),
      dayKey: dayKeyArg.nullable(),
      note: z.string().max(1000).nullable(),
    }),
    summarize: (a) => `Set mood to ${a.value}${a.dayKey ? ` for ${a.dayKey}` : " for today"}`,
    execute: async (ctx, a) => {
      const dayKey = a.dayKey ?? todayKey(ctx.settings);
      if (dayKey > todayKey(ctx.settings)) throw new ApiError(400, "future_day", "Cannot set future mood");
      await db
        .insert(moodEntries)
        .values({ userId: ctx.userId, dayKey, value: a.value, note: a.note })
        .onConflictDoUpdate({
          target: [moodEntries.userId, moodEntries.dayKey],
          set: { value: a.value, note: a.note, updatedAt: new Date() },
        });
      await recomputeFor(ctx, dayKey);
      return { dayKey, value: a.value };
    },
  }),
  create_goal: mutating({
    description: "Create a goal in the active block (or free-standing).",
    args: z.strictObject({
      title: z.string().min(1).max(200),
      description: z.string().max(2000).nullable(),
    }),
    summarize: (a) => `Create goal "${a.title}"`,
    execute: async (ctx, a) => {
      const { activeBlockFor } = await import("../scoring/snapshot");
      const block = await activeBlockFor(ctx.userId, todayKey(ctx.settings));
      const [row] = await db
        .insert(goals)
        .values({ userId: ctx.userId, title: a.title, description: a.description, blockId: block?.id ?? null })
        .returning();
      return { goalId: row!.id };
    },
  }),
  update_goal: mutating({
    description: "Update a goal's title, status, or track status.",
    args: z.strictObject({
      goalId: z.string().uuid(),
      title: z.string().min(1).max(200).nullable(),
      status: z.enum(["active", "achieved", "dropped"]).nullable(),
      trackStatus: z.enum(["on_track", "at_risk", "done"]).nullable(),
    }),
    summarize: async (a, ctx) => {
      const g = await db.query.goals.findFirst({
        where: and(eq(goals.id, a.goalId), eq(goals.userId, ctx.userId)),
      });
      const changes = [
        a.title ? `title → "${a.title}"` : null,
        a.status ? `status → ${a.status}` : null,
        a.trackStatus ? `track → ${a.trackStatus.replace("_", " ")}` : null,
      ].filter(Boolean);
      return `Edit goal "${g?.title ?? a.goalId}": ${changes.join(", ")}`;
    },
    execute: async (ctx, a) => {
      await db
        .update(goals)
        .set({
          ...(a.title ? { title: a.title } : {}),
          ...(a.status ? { status: a.status } : {}),
          ...(a.trackStatus ? { trackStatus: a.trackStatus } : {}),
        })
        .where(and(eq(goals.id, a.goalId), eq(goals.userId, ctx.userId)));
      return { goalId: a.goalId };
    },
  }),
  update_vision: mutating({
    description: "Rewrite the user's vision text (dream life).",
    args: z.strictObject({ content: z.string().min(1).max(20_000) }),
    summarize: (a) => `Update vision (${a.content.length} chars)`,
    execute: async (ctx, a) => {
      await db
        .insert(vision)
        .values({ userId: ctx.userId, content: a.content })
        .onConflictDoUpdate({
          target: vision.userId,
          set: { content: a.content, updatedAt: new Date() },
        });
      return { updated: true };
    },
  }),
} as const;

// ---------- memory tools ----------
// Execute inline (no confirm card): automatic post-turn extraction already
// writes memories without confirmation, so an explicit "remember this" during
// the conversation carries the same trust level.

const MEMORY_TOOLS = {
  save_memory: {
    description:
      "Store one durable fact about the user in long-term memory (identity, work, health, appearance, preferences, relationships, context). Use when the user asks you to remember something or states a clearly durable fact.",
    args: z.strictObject({
      category: z.enum([
        "identity",
        "work",
        "health",
        "appearance",
        "preferences",
        "relationships",
        "context",
      ]),
      content: z.string().min(1).max(500),
    }),
    execute: async (ctx: ToolContext, args: { category: string; content: string }) => {
      const { memories } = await import("@/db/schema");
      const [row] = await db
        .insert(memories)
        .values({
          userId: ctx.userId,
          category: args.category,
          content: args.content,
          source: ctx.conversationKind === "seeding" ? "seeding" : "chat",
        })
        .returning();
      return { memoryId: row!.id, saved: true };
    },
  },
  list_memories: {
    description: "Everything currently stored in long-term memory about the user.",
    args: z.strictObject({}),
    execute: async (ctx: ToolContext) => {
      const { memories } = await import("@/db/schema");
      const rows = await db.query.memories.findMany({
        where: eq(memories.userId, ctx.userId),
        orderBy: [asc(memories.category), asc(memories.createdAt)],
      });
      return rows.map((m) => ({ id: m.id, category: m.category, content: m.content }));
    },
  },
} as const;

export type ReadToolName = keyof typeof READ_TOOLS;
export type MutatingToolName = keyof typeof MUTATING_TOOLS;
export type MemoryToolName = keyof typeof MEMORY_TOOLS;

export function isMutatingTool(name: string): name is MutatingToolName {
  return name in MUTATING_TOOLS;
}

export function isReadTool(name: string): name is ReadToolName {
  return name in READ_TOOLS;
}

export function isMemoryTool(name: string): name is MemoryToolName {
  return name in MEMORY_TOOLS;
}

export async function executeMemoryTool(
  ctx: ToolContext,
  name: MemoryToolName,
  rawArgs: unknown,
): Promise<unknown> {
  const tool = MEMORY_TOOLS[name];
  const args = tool.args.parse(rawArgs);
  return (tool.execute as (c: ToolContext, a: unknown) => Promise<unknown>)(ctx, args);
}

/** OpenAI function-tool definitions (strict). */
export function openAIToolDefinitions() {
  const define = (name: string, description: string, schema: z.ZodType) => ({
    type: "function" as const,
    name,
    description,
    parameters: z.toJSONSchema(schema) as Record<string, unknown>,
    strict: true,
  });
  return [
    ...Object.entries(READ_TOOLS).map(([name, t]) => define(name, t.description, t.args)),
    ...Object.entries(MUTATING_TOOLS).map(([name, t]) => define(name, t.description, t.args)),
    ...Object.entries(MEMORY_TOOLS).map(([name, t]) => define(name, t.description, t.args)),
  ];
}

export async function executeReadTool(ctx: ToolContext, name: ReadToolName, rawArgs: unknown): Promise<unknown> {
  const tool = READ_TOOLS[name];
  const args = tool.args.parse(rawArgs);
  return (tool.execute as (c: ToolContext, a: unknown) => Promise<unknown>)(ctx, args);
}

export function validateMutatingArgs(name: MutatingToolName, rawArgs: unknown): unknown {
  return MUTATING_TOOLS[name].args.parse(rawArgs);
}

export async function summarizeMutation(ctx: ToolContext, name: MutatingToolName, args: unknown): Promise<string> {
  return (MUTATING_TOOLS[name].summarize as (a: unknown, c: ToolContext) => Promise<string> | string)(args, ctx);
}

/** Deterministic execution of confirmed action args (model is not re-invoked). */
export async function executeMutation(ctx: ToolContext, name: MutatingToolName, args: unknown): Promise<unknown> {
  return (MUTATING_TOOLS[name].execute as (c: ToolContext, a: unknown) => Promise<unknown>)(ctx, args);
}

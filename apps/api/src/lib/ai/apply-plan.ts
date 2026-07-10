// Applies a USER-EDITED interview result: creates areas, vision, profile,
// block, goals, tactics, habits, and starter tasks. Nothing here trusts the
// model — the payload is what the user approved on the Plan Proposal Review
// screen, re-validated with zod.

import { and, eq, ilike } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/db/client";
import {
  areas,
  blocks,
  goals,
  habits,
  interviewSessions,
  tactics,
  tasks,
  userProfile,
  vision,
} from "@/db/schema";
import type { SettingsRow } from "../auth";
import { BLOCK_LENGTH_DAYS, prepareBlockSlot, snapToMonday } from "../blocks";
import { addDays, isValidDayKey } from "../daykey";
import { ApiError } from "../http";
import { recomputeDay, todayKey } from "../scoring/snapshot";

const applyHabitSchema = z.object({
  name: z.string().min(1).max(120),
  icon: z.string().max(80).nullish(),
  type: z.enum(["daily", "multi_daily", "weekly_frequency"]),
  targetReps: z.number().int().min(1).max(10),
  plannedDays: z.array(z.number().int().min(1).max(7)).max(7).default([]),
});

const applyTaskSchema = z.object({
  title: z.string().min(1).max(300),
  notes: z.string().max(5000).nullish(),
  dueOffsetDays: z.number().int().min(0).max(83).nullish(),
  priority: z.enum(["low", "medium", "high"]).default("medium"),
});

const applyTacticSchema = z
  .object({
    title: z.string().min(1).max(300),
    fromWeek: z.number().int().min(1).max(12),
    toWeek: z.number().int().min(1).max(12),
  })
  .refine((t) => t.fromWeek <= t.toWeek, { message: "fromWeek must be <= toWeek" });

const applyGoalSchema = z.object({
  title: z.string().min(1).max(200),
  description: z.string().max(2000).nullish(),
  targetLine: z.string().max(300).nullish(),
  areaIndex: z.number().int().min(0).nullable(),
  tactics: z.array(applyTacticSchema).max(8).default([]),
  habits: z.array(applyHabitSchema).max(12).default([]),
  tasks: z.array(applyTaskSchema).max(12).default([]),
});

export const applyPayloadSchema = z.object({
  vision: z.string().min(1).max(20_000),
  profile: z.object({
    values: z.array(z.string()),
    constraints: z.array(z.string()),
    schedule: z.string(),
    motivations: z.array(z.string()),
    context: z.string(),
  }),
  areas: z.array(z.object({ name: z.string().min(1).max(60), emoji: z.string().max(16).nullish() })).max(8),
  block: z.object({
    title: z.string().min(1).max(200),
    startDate: z.string().refine(isValidDayKey, { message: "invalid startDate" }).nullish(),
  }),
  goals: z.array(applyGoalSchema).min(1).max(6),
});

export type ApplyPayload = z.infer<typeof applyPayloadSchema>;

export async function applyPlan(
  userId: string,
  settings: SettingsRow,
  sessionId: string,
  payload: ApplyPayload,
): Promise<{ blockId: string }> {
  const session = await db.query.interviewSessions.findFirst({
    where: and(eq(interviewSessions.id, sessionId), eq(interviewSessions.userId, userId)),
  });
  if (!session) throw new ApiError(404, "not_found", "Interview session not found");
  if (session.status === "applied") {
    throw new ApiError(409, "already_applied", "This interview was already applied");
  }
  if (session.status !== "completed") {
    throw new ApiError(409, "interview_incomplete", "Finish the interview before applying");
  }

  const today = todayKey(settings);
  const requestedStart = payload.block.startDate ?? addDays(today, 1);
  const startDate = snapToMonday(requestedStart < today ? today : requestedStart);
  const endDate = addDays(startDate, BLOCK_LENGTH_DAYS);

  // Block invariants: no overlap, at most one active.
  const { hasActive, nextNumber } = await prepareBlockSlot(userId, startDate, endDate);

  // Areas: reuse by (case-insensitive) name, create the rest.
  const areaIds: (string | null)[] = [];
  for (const [index, area] of payload.areas.entries()) {
    const existing = await db.query.areas.findFirst({
      where: and(eq(areas.userId, userId), ilike(areas.name, area.name)),
    });
    if (existing) {
      areaIds.push(existing.id);
    } else {
      const [created] = await db
        .insert(areas)
        .values({ userId, name: area.name, emoji: area.emoji ?? null, sortOrder: index })
        .returning();
      areaIds.push(created?.id ?? null);
    }
  }

  // Vision + profile (upserts).
  await db
    .insert(vision)
    .values({ userId, content: payload.vision })
    .onConflictDoUpdate({ target: vision.userId, set: { content: payload.vision, updatedAt: new Date() } });
  await db
    .insert(userProfile)
    .values({ userId, data: payload.profile })
    .onConflictDoUpdate({ target: userProfile.userId, set: { data: payload.profile, updatedAt: new Date() } });

  const [block] = await db
    .insert(blocks)
    .values({
      userId,
      number: nextNumber,
      title: payload.block.title,
      startDate,
      endDate,
      status: hasActive ? "planned" : "active",
    })
    .returning();
  if (!block) throw new ApiError(500, "internal_error", "Could not create block");

  for (const [goalIndex, goal] of payload.goals.entries()) {
    const areaId = goal.areaIndex !== null ? (areaIds[goal.areaIndex] ?? null) : null;
    const description = [goal.targetLine, goal.description].filter(Boolean).join("\n\n") || null;
    const [createdGoal] = await db
      .insert(goals)
      .values({
        userId,
        blockId: block.id,
        areaId,
        title: goal.title,
        description,
        sortOrder: goalIndex,
      })
      .returning();
    if (!createdGoal) continue;

    if (goal.tactics.length > 0) {
      await db.insert(tactics).values(
        goal.tactics.map((tactic, i) => ({
          userId,
          goalId: createdGoal.id,
          title: tactic.title,
          fromWeek: tactic.fromWeek,
          toWeek: tactic.toWeek,
          sortOrder: i,
        })),
      );
    }

    if (goal.habits.length > 0) {
      await db.insert(habits).values(
        goal.habits.map((habit, i) => ({
          userId,
          name: habit.name,
          icon: habit.icon ?? null,
          type: habit.type,
          targetReps: habit.type === "daily" ? 1 : habit.targetReps,
          plannedDays: habit.type === "weekly_frequency" ? habit.plannedDays : [],
          areaId,
          goalId: createdGoal.id,
          startDate,
          sortOrder: i,
        })),
      );
    }

    if (goal.tasks.length > 0) {
      await db.insert(tasks).values(
        goal.tasks.map((task, i) => ({
          userId,
          title: task.title,
          notes: task.notes ?? null,
          priority: task.priority,
          dueDate: task.dueOffsetDays === null || task.dueOffsetDays === undefined
            ? null
            : addDays(startDate, task.dueOffsetDays),
          goalId: createdGoal.id,
          sortOrder: i,
        })),
      );
    }
  }

  await db
    .update(interviewSessions)
    .set({ status: "applied" })
    .where(eq(interviewSessions.id, session.id));

  await recomputeDay(userId, settings, today);
  return { blockId: block.id };
}

import { NextResponse } from "next/server";
import { and, asc, eq, inArray, ne } from "drizzle-orm";
import { db } from "@/db/client";
import { goalMilestones, goals } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { goalProgress } from "@/lib/goals";
import { ApiError, handler, parseBody, parseQuery } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { goalCreateSchema, goalListQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

type GoalRow = typeof goals.$inferSelect;
type MilestoneRow = typeof goalMilestones.$inferSelect;

/** A goal plus its milestones and both progress fractions. */
export function serializeGoal(goal: GoalRow, milestones: MilestoneRow[], today: string) {
  return {
    ...goal,
    milestones: milestones.map((m) => ({
      id: m.id,
      goalId: m.goalId,
      title: m.title,
      doneAt: m.doneAt,
      sortOrder: m.sortOrder,
    })),
    ...goalProgress(goal, milestones, today),
  };
}

/** Every goal in `rows` with its milestones attached — one extra query. */
export async function withMilestones(userId: string, rows: GoalRow[], today: string) {
  if (rows.length === 0) return [];
  const milestones = await db.query.goalMilestones.findMany({
    where: and(
      eq(goalMilestones.userId, userId),
      inArray(goalMilestones.goalId, rows.map((g) => g.id)),
    ),
    orderBy: [asc(goalMilestones.sortOrder), asc(goalMilestones.createdAt)],
  });
  const byGoal = new Map<string, MilestoneRow[]>();
  for (const m of milestones) {
    const list = byGoal.get(m.goalId) ?? [];
    list.push(m);
    byGoal.set(m.goalId, list);
  }
  return rows.map((g) => serializeGoal(g, byGoal.get(g.id) ?? [], today));
}

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, goalListQuerySchema);

  const rows = await db.query.goals.findMany({
    where:
      query.includeClosed === "true"
        ? eq(goals.userId, ctx.userId)
        : and(eq(goals.userId, ctx.userId), ne(goals.status, "dropped")),
    orderBy: [asc(goals.sortOrder), asc(goals.targetDate), asc(goals.createdAt)],
  });

  return NextResponse.json({
    goals: await withMilestones(ctx.userId, rows, todayKey(ctx.settings)),
  });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, goalCreateSchema);
  const today = todayKey(ctx.settings);
  const startDate = body.startDate ?? today;

  if (startDate > body.targetDate) {
    throw new ApiError(400, "validation_error", "targetDate must be on or after startDate");
  }

  const [created] = await db
    .insert(goals)
    .values({
      id: body.id,
      userId: ctx.userId,
      title: body.title,
      description: body.description ?? null,
      horizon: body.horizon ?? "short",
      areaId: body.areaId ?? null,
      startDate,
      targetDate: body.targetDate,
      unit: body.unit ?? null,
      startValue: body.startValue ?? null,
      targetValue: body.targetValue ?? null,
      // An untouched goal sits at its baseline rather than at "no reading
      // yet", so the first progress bar renders at 0% instead of blank.
      currentValue: body.currentValue ?? body.startValue ?? null,
      sortOrder: body.sortOrder ?? 0,
    })
    // The id is client-chosen so an offline-queued create can be replayed.
    .onConflictDoNothing()
    .returning();

  if (!created) {
    // Replay of a create that already landed — return the stored goal.
    const existing = body.id
      ? await db.query.goals.findFirst({
          where: and(eq(goals.id, body.id), eq(goals.userId, ctx.userId)),
        })
      : undefined;
    if (!existing) throw new ApiError(500, "internal_error", "Could not create goal");
    return NextResponse.json(
      await withMilestones(ctx.userId, [existing], today).then((g) => g[0]),
    );
  }

  return NextResponse.json(serializeGoal(created, [], today), { status: 201 });
});

import { NextResponse } from "next/server";
import { and, asc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { goals, tactics } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, parseQuery } from "@/lib/http";
import { completedWeeksByTactic, type TacticRow } from "@/lib/tactics";
import { tacticCreateSchema, tacticListQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, tacticListQuerySchema);

  let rows: TacticRow[];
  if (query.goalId) {
    rows = await db.query.tactics.findMany({
      where: and(eq(tactics.userId, ctx.userId), eq(tactics.goalId, query.goalId)),
      orderBy: [asc(tactics.sortOrder), asc(tactics.createdAt)],
    });
  } else if (query.blockId) {
    const joined = await db
      .select({ tactic: tactics })
      .from(tactics)
      .innerJoin(goals, eq(tactics.goalId, goals.id))
      .where(and(eq(tactics.userId, ctx.userId), eq(goals.blockId, query.blockId)))
      .orderBy(asc(goals.sortOrder), asc(tactics.sortOrder), asc(tactics.createdAt));
    rows = joined.map((r) => r.tactic);
  } else {
    // Unreachable: the query schema requires exactly one of goalId/blockId.
    throw new ApiError(400, "validation_error", "provide exactly one of goalId or blockId");
  }

  const completions = await completedWeeksByTactic(rows.map((t) => t.id));
  return NextResponse.json({
    tactics: rows.map((t) => ({ ...t, completedWeeks: completions.get(t.id) ?? [] })),
  });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, tacticCreateSchema);

  const goal = await db.query.goals.findFirst({
    where: and(eq(goals.id, body.goalId), eq(goals.userId, ctx.userId)),
  });
  if (!goal) throw new ApiError(404, "not_found", "Goal not found");

  const [created] = await db
    .insert(tactics)
    .values({
      userId: ctx.userId,
      goalId: body.goalId,
      title: body.title,
      fromWeek: body.fromWeek,
      toWeek: body.toWeek,
      sortOrder: body.sortOrder ?? 0,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create tactic");

  return NextResponse.json({ ...created, completedWeeks: [] }, { status: 201 });
});

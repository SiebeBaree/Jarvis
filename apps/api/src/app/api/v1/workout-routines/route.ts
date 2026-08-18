// Routines: the user's own templates ("Leg day", "Chest & Back"). Nothing is
// generated — the list is exactly what was written, in the order it was
// written.

import { NextResponse } from "next/server";
import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";
import { db } from "@/db/client";
import { workoutRoutineExercises, workoutRoutines, workoutSessions } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, parseQuery, resolveIdempotentCreate } from "@/lib/http";
import { isUniqueViolation } from "@/lib/metrics";
import { replaceRoutineExercises, routineDetail } from "@/lib/training";
import { exercisesQuerySchema, routineCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, exercisesQuerySchema);

  const rows = await db.query.workoutRoutines.findMany({
    where:
      query.includeArchived === "true"
        ? eq(workoutRoutines.userId, ctx.userId)
        : and(eq(workoutRoutines.userId, ctx.userId), isNull(workoutRoutines.archivedAt)),
    orderBy: [asc(workoutRoutines.sortOrder), asc(workoutRoutines.name)],
  });

  if (rows.length === 0) return NextResponse.json({ routines: [] });
  const routineIds = rows.map((row) => row.id);

  // Two aggregates rather than N+1: how many movements the routine holds, and
  // when it was last actually trained (the card's subtitle).
  const [counts, lastPerformed] = await Promise.all([
    db
      .select({
        routineId: workoutRoutineExercises.routineId,
        count: sql<number>`count(*)::int`,
      })
      .from(workoutRoutineExercises)
      .where(inArray(workoutRoutineExercises.routineId, routineIds))
      .groupBy(workoutRoutineExercises.routineId),
    db
      .select({
        routineId: workoutSessions.routineId,
        dayKey: sql<string>`max(${workoutSessions.dayKey})`,
      })
      .from(workoutSessions)
      .where(
        and(
          eq(workoutSessions.userId, ctx.userId),
          inArray(workoutSessions.routineId, routineIds),
        ),
      )
      .groupBy(workoutSessions.routineId),
  ]);

  const countBy = new Map(counts.map((row) => [row.routineId, row.count]));
  const lastBy = new Map(lastPerformed.map((row) => [row.routineId, row.dayKey]));

  return NextResponse.json({
    routines: rows.map((row) => ({
      id: row.id,
      name: row.name,
      emoji: row.emoji,
      colorHex: row.colorHex,
      notes: row.notes,
      sortOrder: row.sortOrder,
      archived: row.archivedAt !== null,
      exerciseCount: countBy.get(row.id) ?? 0,
      lastPerformedDayKey: lastBy.get(row.id) ?? null,
    })),
  });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, routineCreateSchema);
  const name = body.name.trim();

  const insert = db.insert(workoutRoutines).values({
    id: body.id,
    userId: ctx.userId,
    name,
    emoji: body.emoji ?? null,
    colorHex: body.colorHex ?? null,
    notes: body.notes ?? null,
    sortOrder: body.sortOrder ?? 0,
  });

  let routineId: string;
  let status = 201;
  try {
    const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();
    if (created) {
      routineId = created.id;
    } else {
      const existing = await resolveIdempotentCreate(ctx.userId, "routine", () =>
        db.query.workoutRoutines.findFirst({ where: eq(workoutRoutines.id, body.id!) }),
      );
      routineId = existing.id;
      status = 200;
    }
  } catch (err) {
    if (isUniqueViolation(err)) {
      throw new ApiError(409, "name_exists", `A routine named "${name}" already exists`);
    }
    throw err;
  }

  if (body.exercises) {
    await replaceRoutineExercises(ctx.userId, routineId, body.exercises);
  }

  // Same shape as PATCH, so the editor has one response type to decode.
  return NextResponse.json(await routineDetail(ctx.userId, routineId), { status });
});

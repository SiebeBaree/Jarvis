// The user's exercise catalogue. Exercises are shared across routines and
// sessions, which is what makes "how has my bench moved in six months" a
// question the data can answer at all.

import { NextResponse } from "next/server";
import { and, asc, eq, isNull } from "drizzle-orm";
import { db } from "@/db/client";
import { exercises } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, parseQuery, resolveIdempotentCreate } from "@/lib/http";
import { isUniqueViolation } from "@/lib/metrics";
import { exerciseCreateSchema, exercisesQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, exercisesQuerySchema);

  const rows = await db.query.exercises.findMany({
    where:
      query.includeArchived === "true"
        ? eq(exercises.userId, ctx.userId)
        : and(eq(exercises.userId, ctx.userId), isNull(exercises.archivedAt)),
    orderBy: [asc(exercises.name)],
  });
  return NextResponse.json({ exercises: rows });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, exerciseCreateSchema);
  const name = body.name.trim();

  const insert = db.insert(exercises).values({
    id: body.id,
    userId: ctx.userId,
    name,
    muscleGroup: body.muscleGroup ?? null,
    equipment: body.equipment ?? null,
    isBodyweight: body.isBodyweight ?? false,
    notes: body.notes ?? null,
  });

  try {
    const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();
    if (created) return NextResponse.json(created, { status: 201 });
    const existing = await resolveIdempotentCreate(ctx.userId, "exercise", () =>
      db.query.exercises.findFirst({ where: eq(exercises.id, body.id!) }),
    );
    return NextResponse.json(existing);
  } catch (err) {
    // Same name, different id: the user is adding a movement they already
    // have. Handing back the existing one is what they meant — a second
    // "Bench press" row would split its own history in half.
    if (isUniqueViolation(err)) {
      const existing = await db.query.exercises.findFirst({
        where: and(eq(exercises.userId, ctx.userId), eq(exercises.name, name)),
      });
      if (existing) return NextResponse.json(existing);
      throw new ApiError(409, "name_exists", `An exercise named "${name}" already exists`);
    }
    throw err;
  }
});

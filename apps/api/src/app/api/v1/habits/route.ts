import { NextResponse } from "next/server";
import { and, asc, eq, isNull, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { habits } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";
import { habitCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

const DEFAULT_TARGET_REPS = { daily: 1, multi_daily: 2, weekly_frequency: 3 } as const;

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const includeArchived =
    new URL(request.url).searchParams.get("includeArchived") === "true";

  const conditions: SQL[] = [eq(habits.userId, ctx.userId)];
  if (!includeArchived) conditions.push(isNull(habits.archivedAt));

  const rows = await db.query.habits.findMany({
    where: and(...conditions),
    orderBy: [asc(habits.sortOrder), asc(habits.createdAt)],
  });
  return NextResponse.json({ habits: rows });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, habitCreateSchema);
  const today = todayKey(ctx.settings);

  const insert = db.insert(habits).values({
    id: body.id,
    userId: ctx.userId,
    name: body.name,
    icon: body.icon ?? null,
    colorHex: body.colorHex ?? null,
    type: body.type,
    targetReps: body.targetReps ?? DEFAULT_TARGET_REPS[body.type],
    plannedDays: body.plannedDays ?? [],
    areaId: body.areaId ?? null,
    startDate: body.startDate ?? today,
    sortOrder: body.sortOrder ?? 0,
  });
  // A client-chosen id makes a retried create a no-op instead of a duplicate,
  // which is what lets habit creation go through the offline outbox.
  const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();

  if (!created) {
    if (!body.id) throw new ApiError(500, "internal_error", "Could not create habit");
    const existing = await db.query.habits.findFirst({ where: eq(habits.id, body.id) });
    if (!existing) throw new ApiError(500, "internal_error", "Could not create habit");
    if (existing.userId !== ctx.userId) {
      throw new ApiError(409, "id_conflict", "That habit id is already taken");
    }
    return NextResponse.json(existing);
  }

  await recomputeDay(ctx.userId, ctx.settings, today);
  return NextResponse.json(created, { status: 201 });
});

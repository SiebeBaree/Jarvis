import { NextResponse } from "next/server";
import { and, desc, eq, gte, lte, sql } from "drizzle-orm";
import { db } from "@/db/client";
import { habitCompletions, habits } from "@/db/schema";
import { requireAuth, type AuthContext } from "@/lib/auth";
import { weekEnd, weekStart } from "@/lib/daykey";
import { ApiError, handler } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";
import { habitLogSchema } from "@/lib/validation";

export const runtime = "nodejs";

/** Like parseBody but tolerates an empty body (dayKey is optional). */
async function parseLogBody(request: Request): Promise<{ dayKey?: string }> {
  const text = await request.text();
  if (!text.trim()) return {};
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON");
  }
  const result = habitLogSchema.safeParse(raw);
  if (!result.success) {
    throw new ApiError(
      400,
      "validation_error",
      result.error.issues.map((i) => i.message).join("; "),
    );
  }
  return result.data;
}

async function loadHabit(ctx: AuthContext, id: string) {
  const habit = await db.query.habits.findFirst({
    where: and(eq(habits.id, id), eq(habits.userId, ctx.userId)),
  });
  if (!habit) throw new ApiError(404, "not_found", "Habit not found");
  return habit;
}

async function repsOn(ctx: AuthContext, habitId: string, dayKey: string): Promise<number> {
  const [row] = await db
    .select({ n: sql<number>`count(*)::int` })
    .from(habitCompletions)
    .where(
      and(
        eq(habitCompletions.userId, ctx.userId),
        eq(habitCompletions.habitId, habitId),
        eq(habitCompletions.dayKey, dayKey),
      ),
    );
  return row?.n ?? 0;
}

/** { repsToday, weekTotal, credit } after recomputing the day's snapshot. */
async function logResult(ctx: AuthContext, habitId: string, dayKey: string) {
  const snapshot = await recomputeDay(ctx.userId, ctx.settings, dayKey);
  const rows = await db
    .select({ dayKey: habitCompletions.dayKey, n: sql<number>`count(*)::int` })
    .from(habitCompletions)
    .where(
      and(
        eq(habitCompletions.userId, ctx.userId),
        eq(habitCompletions.habitId, habitId),
        gte(habitCompletions.dayKey, weekStart(dayKey)),
        lte(habitCompletions.dayKey, weekEnd(dayKey)),
      ),
    )
    .groupBy(habitCompletions.dayKey);

  let repsToday = 0;
  let weekTotal = 0;
  for (const row of rows) {
    weekTotal += row.n;
    if (row.dayKey === dayKey) repsToday = row.n;
  }
  const credit = snapshot.breakdown.habits.find((h) => h.habitId === habitId)?.credit ?? 0;
  return { repsToday, weekTotal, credit };
}

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const habit = await loadHabit(ctx, id);
    const body = await parseLogBody(request);

    const today = todayKey(ctx.settings);
    const dayKey = body.dayKey ?? today;
    if (dayKey > today) throw new ApiError(400, "future_day", "Cannot log a future day");
    if (dayKey < habit.startDate) {
      throw new ApiError(400, "before_start", "Cannot log before the habit's start date");
    }

    const reps = await repsOn(ctx, id, dayKey);
    if (habit.type === "daily" && reps >= 1) {
      throw new ApiError(409, "already_logged", "Habit already logged for that day");
    }
    if (habit.type === "multi_daily" && reps >= habit.targetReps) {
      throw new ApiError(409, "target_reached", "Daily target already reached");
    }

    await db.insert(habitCompletions).values({ userId: ctx.userId, habitId: id, dayKey });
    return NextResponse.json(await logResult(ctx, id, dayKey));
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    await loadHabit(ctx, id);
    const body = await parseLogBody(request);

    const dayKey = body.dayKey ?? todayKey(ctx.settings);
    const latest = await db.query.habitCompletions.findFirst({
      where: and(
        eq(habitCompletions.userId, ctx.userId),
        eq(habitCompletions.habitId, id),
        eq(habitCompletions.dayKey, dayKey),
      ),
      orderBy: [desc(habitCompletions.completedAt)],
    });
    if (!latest) throw new ApiError(404, "no_completion", "No completion to remove for that day");

    await db.delete(habitCompletions).where(eq(habitCompletions.id, latest.id));
    return NextResponse.json(await logResult(ctx, id, dayKey));
  },
);

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { habits } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { buildHabitStats, habitRepsByDay } from "@/lib/habit-stats";
import { ApiError, handler } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";

export const runtime = "nodejs";

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const habit = await db.query.habits.findFirst({
      where: and(eq(habits.id, id), eq(habits.userId, ctx.userId)),
    });
    if (!habit) throw new ApiError(404, "not_found", "Habit not found");

    const repsByDay = await habitRepsByDay(ctx.userId, id);
    const stats = buildHabitStats(habit, ctx.settings, todayKey(ctx.settings), repsByDay);
    return NextResponse.json(stats);
  },
);

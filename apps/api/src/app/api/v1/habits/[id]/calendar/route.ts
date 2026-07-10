import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { habits } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { addDays, weekEnd, weekStart } from "@/lib/daykey";
import { habitRepsByDay, round2 } from "@/lib/habit-stats";
import { ApiError, handler, parseQuery } from "@/lib/http";
import { habitApplicable, todayKey } from "@/lib/scoring/snapshot";
import { calendarQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

type DayState = "full" | "partial" | "none" | "not_applicable";

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const query = parseQuery(request, calendarQuerySchema);

    const habit = await db.query.habits.findFirst({
      where: and(eq(habits.id, id), eq(habits.userId, ctx.userId)),
    });
    if (!habit) throw new ApiError(404, "not_found", "Habit not found");

    const [yearStr, monthStr] = query.month.split("-");
    const year = Number(yearStr);
    const month = Number(monthStr);
    if (month < 1 || month > 12) {
      throw new ApiError(400, "invalid_month", "month must be YYYY-MM with MM in 01-12");
    }
    const monthStart = `${query.month}-01`;
    const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
    const monthEnd = `${query.month}-${String(daysInMonth).padStart(2, "0")}`;
    const today = todayKey(ctx.settings);

    // Full surrounding weeks so weekly totals are correct at month edges.
    const repsByDay = await habitRepsByDay(
      ctx.userId,
      id,
      weekStart(monthStart),
      weekEnd(monthEnd),
    );

    const target = Math.max(1, habit.targetReps);
    const isWeekly = habit.type === "weekly_frequency";

    const days: {
      dayKey: string;
      reps: number;
      target: number;
      credit: number | null;
      state: DayState;
    }[] = [];
    const lastDay = monthEnd < today ? monthEnd : today;
    for (let day = monthStart; day <= lastDay; day = addDays(day, 1)) {
      const reps = repsByDay.get(day) ?? 0;
      const applicable = habitApplicable(habit, day, ctx.settings);
      let state: DayState;
      if (!applicable) {
        state = "not_applicable";
      } else if (isWeekly) {
        state = reps > 0 ? "full" : "none"; // a gym visit is binary
      } else {
        state = reps >= target ? "full" : reps > 0 ? "partial" : "none";
      }
      days.push({
        dayKey: day,
        reps,
        target: habit.targetReps,
        credit: !applicable || isWeekly ? null : round2(Math.min(1, reps / target)),
        state,
      });
    }

    let weeks: { weekStart: string; total: number; target: number; result: string }[] | null =
      null;
    if (isWeekly) {
      weeks = [];
      for (let ws = weekStart(monthStart); ws <= monthEnd; ws = addDays(ws, 7)) {
        let total = 0;
        for (let day = ws; day <= weekEnd(ws); day = addDays(day, 1)) {
          total += repsByDay.get(day) ?? 0;
        }
        const result = weekEnd(ws) >= today ? "live" : total >= target ? "met" : "missed";
        weeks.push({ weekStart: ws, total, target: habit.targetReps, result });
      }
    }

    return NextResponse.json({ days, weeks });
  },
);

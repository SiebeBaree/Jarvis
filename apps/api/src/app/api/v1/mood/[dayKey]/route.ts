import { NextResponse } from "next/server";
import { db } from "@/db/client";
import { moodEntries } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { isValidDayKey } from "@/lib/daykey";
import { ApiError, handler, parseBody } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";
import { moodPutSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PUT = handler(
  async (request: Request, { params }: { params: Promise<{ dayKey: string }> }) => {
    const ctx = await requireAuth(request);
    const { dayKey } = await params;
    if (!isValidDayKey(dayKey)) {
      throw new ApiError(400, "invalid_day_key", "dayKey must be a valid YYYY-MM-DD date");
    }
    if (dayKey > todayKey(ctx.settings)) {
      throw new ApiError(400, "future_day", "Cannot set mood for a future day");
    }

    const body = await parseBody(request, moodPutSchema);
    const note = body.note ?? null;

    await db
      .insert(moodEntries)
      .values({ userId: ctx.userId, dayKey, value: body.value, note })
      .onConflictDoUpdate({
        target: [moodEntries.userId, moodEntries.dayKey],
        set: { value: body.value, note, updatedAt: new Date() },
      });

    const score = await recomputeDay(ctx.userId, ctx.settings, dayKey);
    return NextResponse.json({ mood: { dayKey, value: body.value, note }, score });
  },
);

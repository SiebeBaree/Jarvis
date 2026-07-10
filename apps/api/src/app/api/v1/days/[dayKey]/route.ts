import { NextResponse } from "next/server";
import { requireAuth } from "@/lib/auth";
import { isValidDayKey } from "@/lib/daykey";
import { ApiError, handler } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { buildDayPayload } from "@/lib/today";

export const runtime = "nodejs";

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ dayKey: string }> }) => {
    const ctx = await requireAuth(request);
    const { dayKey } = await params;
    if (!isValidDayKey(dayKey)) {
      throw new ApiError(400, "invalid_day_key", "dayKey must be a valid YYYY-MM-DD date");
    }
    if (dayKey > todayKey(ctx.settings)) {
      throw new ApiError(400, "future_day", "Cannot view a future day");
    }
    const payload = await buildDayPayload(ctx.userId, ctx.settings, dayKey, { isToday: false });
    return NextResponse.json(payload);
  },
);

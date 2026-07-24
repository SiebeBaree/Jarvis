import { NextResponse } from "next/server";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { buildDayPayload } from "@/lib/today";

export const runtime = "nodejs";
export const maxDuration = 30; // cold start + Neon wake must not be cut short

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const payload = await buildDayPayload(ctx.userId, ctx.settings, todayKey(ctx.settings), {
    isToday: true,
  });
  return NextResponse.json(payload);
});

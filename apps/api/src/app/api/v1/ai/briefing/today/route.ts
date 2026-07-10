import { NextResponse } from "next/server";
import { getBriefing } from "@/lib/ai/briefing";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";

export const runtime = "nodejs";
export const maxDuration = 60; // first request of the day generates the briefing

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);

  const briefing = await getBriefing(ctx.userId, ctx.settings, "morning");
  return NextResponse.json({
    dayKey: briefing.dayKey,
    kind: briefing.kind,
    content: briefing.content,
    createdAt: briefing.createdAt,
  });
});

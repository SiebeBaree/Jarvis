import { NextResponse } from "next/server";
import { getWrapup } from "@/lib/ai/briefing";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";

export const runtime = "nodejs";
export const maxDuration = 60; // regenerates when the day materially changed

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);

  const briefing = await getWrapup(ctx.userId, ctx.settings);
  return NextResponse.json({
    dayKey: briefing.dayKey,
    kind: briefing.kind,
    content: briefing.content,
    createdAt: briefing.createdAt,
  });
});

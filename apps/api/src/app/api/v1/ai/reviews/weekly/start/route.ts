// Starts (or returns) the weekly-review conversation for a block week.
// No model call here — the app talks to the conversation via POST /ai/chat,
// which seeds review conversations with computed stats (lib/reviews.ts).

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { conversations } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { addDays, weekIndexInBlock } from "@/lib/daykey";
import { ApiError, handler } from "@/lib/http";
import { activeBlockFor, todayKey } from "@/lib/scoring/snapshot";
import { weeklyReviewStartSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);

  // Body is optional: absent/empty body means "default week".
  const raw = await request.text();
  let parsedRaw: unknown = {};
  if (raw.trim().length > 0) {
    try {
      parsedRaw = JSON.parse(raw);
    } catch {
      throw new ApiError(400, "invalid_json", "Request body must be valid JSON");
    }
  }
  const body = weeklyReviewStartSchema.parse(parsedRaw);

  const today = todayKey(ctx.settings);
  const block = await activeBlockFor(ctx.userId, today);
  if (!block) throw new ApiError(409, "no_active_block", "No active block covers today");

  // Default: the week that just ended — a Monday review targets last week.
  const yesterdayWeek = weekIndexInBlock(addDays(today, -1), block.startDate);
  const weekNumber = body.weekNumber ?? Math.min(13, Math.max(1, yesterdayWeek));

  const existing = await db.query.conversations.findFirst({
    where: and(
      eq(conversations.userId, ctx.userId),
      eq(conversations.kind, "weekly_review"),
      eq(conversations.blockId, block.id),
      eq(conversations.weekNumber, weekNumber),
    ),
  });
  if (existing) return NextResponse.json({ conversation: existing, existing: true });

  const [created] = await db
    .insert(conversations)
    .values({
      userId: ctx.userId,
      kind: "weekly_review",
      blockId: block.id,
      weekNumber,
      title: `Week ${weekNumber} review`,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create conversation");

  return NextResponse.json({ conversation: created, existing: false }, { status: 201 });
});

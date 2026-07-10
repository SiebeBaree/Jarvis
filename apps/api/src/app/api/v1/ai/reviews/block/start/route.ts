// Starts (or returns) THE block-review retrospective conversation — one per
// block. No model call here; the app talks to it via POST /ai/chat, which
// seeds it with 12-week stats (lib/reviews.ts). The next block is designed by
// the "reonboarding" interview from the Plan tab, not by this conversation.

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { conversations } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";
import { activeBlockFor, todayKey } from "@/lib/scoring/snapshot";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);

  const today = todayKey(ctx.settings);
  const block = await activeBlockFor(ctx.userId, today);
  if (!block) throw new ApiError(409, "no_active_block", "No active block covers today");

  const existing = await db.query.conversations.findFirst({
    where: and(
      eq(conversations.userId, ctx.userId),
      eq(conversations.kind, "block_review"),
      eq(conversations.blockId, block.id),
    ),
  });
  if (existing) return NextResponse.json({ conversation: existing, existing: true });

  const [created] = await db
    .insert(conversations)
    .values({
      userId: ctx.userId,
      kind: "block_review",
      blockId: block.id,
      title: `Block ${block.number} retrospective`,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create conversation");

  return NextResponse.json({ conversation: created, existing: false }, { status: 201 });
});

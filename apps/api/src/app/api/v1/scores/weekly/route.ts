// Per-week score averages for one block — the Trends "weekly averages" card
// and the review recap decks.

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { weeklyScoreAverages } from "@/lib/blocks";
import { ApiError, handler, parseQuery } from "@/lib/http";
import { weeklyScoresQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const { blockId } = parseQuery(request, weeklyScoresQuerySchema);

  const block = await db.query.blocks.findFirst({
    where: and(eq(blocks.id, blockId), eq(blocks.userId, ctx.userId)),
  });
  if (!block) throw new ApiError(404, "not_found", "Block not found");

  return NextResponse.json({ weeks: await weeklyScoreAverages(ctx.userId, block) });
});

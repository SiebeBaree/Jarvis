import { NextResponse } from "next/server";
import { and, asc, eq, gte, lte } from "drizzle-orm";
import { db } from "@/db/client";
import { dailyScores } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { addDays, diffDays } from "@/lib/daykey";
import { ApiError, handler, parseQuery } from "@/lib/http";
import { scoresQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, scoresQuerySchema);

  let { from } = query;
  const { to } = query;
  if (from > to) throw new ApiError(400, "invalid_range", "from must be on or before to");
  // Clamp the range to at most 365 days ending at `to`.
  if (diffDays(from, to) >= 365) from = addDays(to, -364);

  const rows = await db.query.dailyScores.findMany({
    where: and(
      eq(dailyScores.userId, ctx.userId),
      gte(dailyScores.dayKey, from),
      lte(dailyScores.dayKey, to),
    ),
    orderBy: [asc(dailyScores.dayKey)],
  });

  return NextResponse.json({
    scores: rows.map((r) => ({
      dayKey: r.dayKey,
      total: r.total,
      taskPoints: r.taskPoints,
      habitPoints: r.habitPoints,
      feelPoints: r.feelPoints,
      isFinal: r.isFinal,
    })),
  });
});

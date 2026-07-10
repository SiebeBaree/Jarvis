import { NextResponse } from "next/server";
import { and, asc, eq, gte, lte } from "drizzle-orm";
import { db } from "@/db/client";
import { moodEntries } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseQuery } from "@/lib/http";
import { scoresQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, scoresQuerySchema);

  const rows = await db.query.moodEntries.findMany({
    where: and(
      eq(moodEntries.userId, ctx.userId),
      gte(moodEntries.dayKey, query.from),
      lte(moodEntries.dayKey, query.to),
    ),
    orderBy: [asc(moodEntries.dayKey)],
  });

  return NextResponse.json({
    moods: rows.map((r) => ({ dayKey: r.dayKey, value: r.value, note: r.note })),
  });
});

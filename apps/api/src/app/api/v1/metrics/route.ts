// Metric entries ascending by day — feeds the Body charts. With typeId one
// type's entries; without, every type's (the Body screen loads all at once).

import { NextResponse } from "next/server";
import { and, asc, eq, gte, lte, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { metricEntries } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseQuery } from "@/lib/http";
import { loadMetricType } from "@/lib/metrics";
import { metricEntriesQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, metricEntriesQuerySchema);

  const conditions: SQL[] = [eq(metricEntries.userId, ctx.userId)];
  if (query.typeId) {
    await loadMetricType(ctx.userId, query.typeId); // 404 when not owned
    conditions.push(eq(metricEntries.metricTypeId, query.typeId));
  }
  if (query.from) conditions.push(gte(metricEntries.dayKey, query.from));
  if (query.to) conditions.push(lte(metricEntries.dayKey, query.to));

  const rows = await db.query.metricEntries.findMany({
    where: and(...conditions),
    orderBy: [asc(metricEntries.dayKey)],
  });

  return NextResponse.json({
    entries: rows.map((r) => ({
      id: r.id,
      metricTypeId: r.metricTypeId,
      dayKey: r.dayKey,
      value: r.value,
    })),
  });
});

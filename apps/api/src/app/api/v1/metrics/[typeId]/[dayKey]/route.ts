// One metric value per (type, day): PUT upserts, DELETE removes.

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { metricEntries } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { isValidDayKey } from "@/lib/daykey";
import { ApiError, handler, parseBody } from "@/lib/http";
import { loadMetricType } from "@/lib/metrics";
import { todayKey } from "@/lib/scoring/snapshot";
import { metricEntryPutSchema } from "@/lib/validation";

export const runtime = "nodejs";

function validDayKeyParam(dayKey: string): string {
  if (!isValidDayKey(dayKey)) {
    throw new ApiError(400, "invalid_day_key", "dayKey must be a valid YYYY-MM-DD date");
  }
  return dayKey;
}

export const PUT = handler(
  async (request: Request, { params }: { params: Promise<{ typeId: string; dayKey: string }> }) => {
    const ctx = await requireAuth(request);
    const { typeId, dayKey: rawDayKey } = await params;
    const dayKey = validDayKeyParam(rawDayKey);
    if (dayKey > todayKey(ctx.settings)) {
      throw new ApiError(400, "future_day", "Cannot log a metric for a future day");
    }

    await loadMetricType(ctx.userId, typeId); // 404 when not owned
    const body = await parseBody(request, metricEntryPutSchema);

    const [entry] = await db
      .insert(metricEntries)
      .values({ userId: ctx.userId, metricTypeId: typeId, dayKey, value: body.value })
      .onConflictDoUpdate({
        target: [metricEntries.metricTypeId, metricEntries.dayKey],
        set: { value: body.value },
      })
      .returning();
    if (!entry) throw new ApiError(500, "internal_error", "Could not save metric entry");

    return NextResponse.json({
      id: entry.id,
      metricTypeId: entry.metricTypeId,
      dayKey: entry.dayKey,
      value: entry.value,
    });
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ typeId: string; dayKey: string }> }) => {
    const ctx = await requireAuth(request);
    const { typeId, dayKey: rawDayKey } = await params;
    const dayKey = validDayKeyParam(rawDayKey);

    const deleted = await db
      .delete(metricEntries)
      .where(
        and(
          eq(metricEntries.userId, ctx.userId),
          eq(metricEntries.metricTypeId, typeId),
          eq(metricEntries.dayKey, dayKey),
        ),
      )
      .returning({ id: metricEntries.id });
    if (deleted.length === 0) throw new ApiError(404, "not_found", "No entry for that day");

    return NextResponse.json({ ok: true });
  },
);

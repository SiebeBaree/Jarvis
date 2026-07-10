import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { metricTypes } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { isUniqueViolation, loadMetricType } from "@/lib/metrics";
import { metricTypePatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, metricTypePatchSchema);

    const existing = await loadMetricType(ctx.userId, id);

    const set: Partial<typeof metricTypes.$inferInsert> = {};
    if (patch.name !== undefined) set.name = patch.name;
    if (patch.unit !== undefined) set.unit = patch.unit;
    if (patch.decimals !== undefined) set.decimals = patch.decimals;
    if (patch.goalValue !== undefined) set.goalValue = patch.goalValue;
    if (patch.goalDirection !== undefined) set.goalDirection = patch.goalDirection;
    if (patch.archived === true) set.archivedAt = existing.archivedAt ?? new Date();
    if (patch.archived === false) set.archivedAt = null;

    if (Object.keys(set).length === 0) return NextResponse.json(existing);

    try {
      const [updated] = await db
        .update(metricTypes)
        .set(set)
        .where(and(eq(metricTypes.id, id), eq(metricTypes.userId, ctx.userId)))
        .returning();
      if (!updated) throw new ApiError(404, "not_found", "Metric type not found");
      return NextResponse.json(updated);
    } catch (err) {
      if (isUniqueViolation(err)) {
        throw new ApiError(409, "name_exists", "A metric type with that name already exists");
      }
      throw err;
    }
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    await loadMetricType(ctx.userId, id);

    // Hard delete; metric_entries cascade via FK.
    await db
      .delete(metricTypes)
      .where(and(eq(metricTypes.id, id), eq(metricTypes.userId, ctx.userId)));
    return NextResponse.json({ ok: true });
  },
);

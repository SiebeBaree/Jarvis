// Shared body-metric helpers: ownership loading and unique-violation detection.

import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { metricTypes } from "@/db/schema";
import { ApiError } from "./http";

export type MetricTypeRow = typeof metricTypes.$inferSelect;

/** Loads a metric type scoped to the user. Throws 404. */
export async function loadMetricType(userId: string, id: string): Promise<MetricTypeRow> {
  const row = await db.query.metricTypes.findFirst({
    where: and(eq(metricTypes.id, id), eq(metricTypes.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Metric type not found");
  return row;
}

/** Postgres unique_violation (23505), possibly wrapped by drizzle. */
export function isUniqueViolation(err: unknown): boolean {
  if (typeof err !== "object" || err === null) return false;
  const e = err as { code?: string; cause?: { code?: string } };
  return e.code === "23505" || e.cause?.code === "23505";
}

// User-defined body metric types (Weight/kg, Body fat/%, ...).

import { NextResponse } from "next/server";
import { and, asc, eq, isNull } from "drizzle-orm";
import { db } from "@/db/client";
import { metricTypes } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, parseQuery } from "@/lib/http";
import { isUniqueViolation } from "@/lib/metrics";
import { metricTypeCreateSchema, metricTypesQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, metricTypesQuerySchema);

  const rows = await db.query.metricTypes.findMany({
    where:
      query.includeArchived === "true"
        ? eq(metricTypes.userId, ctx.userId)
        : and(eq(metricTypes.userId, ctx.userId), isNull(metricTypes.archivedAt)),
    orderBy: [asc(metricTypes.sortOrder), asc(metricTypes.name)],
  });
  return NextResponse.json({ metricTypes: rows });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, metricTypeCreateSchema);

  try {
    const [created] = await db
      .insert(metricTypes)
      .values({
        userId: ctx.userId,
        name: body.name,
        unit: body.unit,
        decimals: body.decimals,
        goalValue: body.goalValue ?? null,
        goalDirection: body.goalDirection ?? null,
      })
      .returning();
    if (!created) throw new ApiError(500, "internal_error", "Could not create metric type");
    return NextResponse.json(created, { status: 201 });
  } catch (err) {
    if (isUniqueViolation(err)) {
      throw new ApiError(409, "name_exists", `A metric type named "${body.name}" already exists`);
    }
    throw err;
  }
});

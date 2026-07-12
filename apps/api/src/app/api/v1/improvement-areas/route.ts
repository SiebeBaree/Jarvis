// Improvement areas (posture, clothing, teeth...): user-defined, weekly photo
// check-ins. GET returns due-this-week state so the Today card can prompt.

import { NextResponse } from "next/server";
import { asc, desc, eq, inArray } from "drizzle-orm";
import { db } from "@/db/client";
import { areaCheckins, improvementAreas } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { buildAreaDTO, weekKeyFor, type CheckinLike } from "@/lib/checkins";
import { ApiError, handler, parseBody, parseQuery } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { improvementAreaCreateSchema } from "@/lib/validation";
import { z } from "zod";

export const runtime = "nodejs";

const listQuerySchema = z.object({ includeArchived: z.enum(["true", "false"]).optional() });

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, listQuerySchema);
  const currentWeek = weekKeyFor(todayKey(ctx.settings));

  const rows = await db.query.improvementAreas.findMany({
    where: eq(improvementAreas.userId, ctx.userId),
    orderBy: [asc(improvementAreas.sortOrder), asc(improvementAreas.createdAt)],
  });
  const visible = query.includeArchived === "true" ? rows : rows.filter((a) => !a.archivedAt);

  // Latest check-in per area in one query.
  const latestByArea = new Map<string, CheckinLike>();
  if (visible.length > 0) {
    const checkins = await db.query.areaCheckins.findMany({
      where: inArray(
        areaCheckins.areaId,
        visible.map((a) => a.id),
      ),
      orderBy: [desc(areaCheckins.weekKey)],
    });
    for (const checkin of checkins) {
      if (!latestByArea.has(checkin.areaId)) latestByArea.set(checkin.areaId, checkin);
    }
  }

  const areas = visible.map((area) =>
    buildAreaDTO(area, latestByArea.get(area.id) ?? null, currentWeek),
  );
  return NextResponse.json({
    areas,
    anyDueThisWeek: areas.some((a) => a.dueThisWeek),
    currentWeekKey: currentWeek,
  });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, improvementAreaCreateSchema);
  try {
    const [row] = await db
      .insert(improvementAreas)
      .values({
        userId: ctx.userId,
        name: body.name,
        emoji: body.emoji ?? null,
        betterLooksLike: body.betterLooksLike ?? null,
        sortOrder: body.sortOrder ?? 0,
      })
      .returning();
    if (!row) throw new ApiError(500, "internal_error", "Could not create area");
    return NextResponse.json(buildAreaDTO(row, null, weekKeyFor(todayKey(ctx.settings))), {
      status: 201,
    });
  } catch (error) {
    if (error instanceof Error && error.message.includes("improvement_areas_user_name_uq")) {
      throw new ApiError(409, "duplicate_name", "An improvement area with that name already exists");
    }
    throw error;
  }
});

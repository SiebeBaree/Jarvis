import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { settings } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";
import { settingsPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  return NextResponse.json(ctx.settings);
});

export const PATCH = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const patch = await parseBody(request, settingsPatchSchema);

  const set: Partial<typeof settings.$inferInsert> = { updatedAt: new Date() };
  if (patch.timezone !== undefined) set.timezone = patch.timezone;
  if (patch.dayBoundaryHour !== undefined) set.dayBoundaryHour = patch.dayBoundaryHour;
  if (patch.weekStartsOn !== undefined) set.weekStartsOn = patch.weekStartsOn;
  if (patch.scoreWeights !== undefined) set.scoreWeights = patch.scoreWeights;
  if (patch.moodScaleMax !== undefined) set.moodScaleMax = patch.moodScaleMax;
  if (patch.checkinNotificationsEnabled !== undefined) {
    set.checkinNotificationsEnabled = patch.checkinNotificationsEnabled;
  }
  if (patch.checkinNotificationHour !== undefined) {
    set.checkinNotificationHour = patch.checkinNotificationHour;
  }

  const [updated] = await db
    .update(settings)
    .set(set)
    .where(eq(settings.userId, ctx.userId))
    .returning();
  if (!updated) throw new ApiError(404, "not_found", "Settings not found");

  const weightsChanged =
    patch.scoreWeights !== undefined &&
    JSON.stringify(patch.scoreWeights) !== JSON.stringify(ctx.settings.scoreWeights);
  if (weightsChanged) {
    await recomputeDay(ctx.userId, updated, todayKey(updated));
  }

  return NextResponse.json(updated);
});

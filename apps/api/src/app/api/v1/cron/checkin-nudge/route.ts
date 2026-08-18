// The daily check-in nudge.
//
// Runs hourly and does almost nothing most of the time: it only has something
// to send in the one hour a user picked, on a day they have not logged a mood.
// The hour comparison happens here rather than in the cron schedule because the
// hour is a user setting in their own timezone, and the schedule is UTC.

import { NextResponse } from "next/server";
import { and, eq, isNull } from "drizzle-orm";
import { db } from "@/db/client";
import { devices, notificationLog, settings as settingsTable } from "@/db/schema";
import { ApiError, handler } from "@/lib/http";
import { sendPush } from "@/lib/notifications/apns";
import { gatherNudgeData, hasMoodFor } from "@/lib/notifications/data";
import { composeCheckinNudge } from "@/lib/notifications/message";
import { localHour, todayKey } from "@/lib/scoring/snapshot";

export const runtime = "nodejs";
export const maxDuration = 30;

const KIND = "checkin_nudge";

type Outcome = { userId: string; result: string; template?: string };

export const GET = handler(async (request: Request) => {
  requireCronSecret(request);

  const now = new Date();
  const rows = await db
    .select()
    .from(settingsTable)
    .where(eq(settingsTable.checkinNotificationsEnabled, true));

  const outcomes: Outcome[] = [];
  for (const settings of rows) {
    outcomes.push(await nudgeUser(settings, now));
  }

  return NextResponse.json({
    checked: rows.length,
    sent: outcomes.filter((o) => o.result === "sent").length,
    outcomes,
  });
});

/**
 * Vercel attaches `Authorization: Bearer $CRON_SECRET` to its cron requests.
 * `requireAuth` cannot apply here, so this is the whole gate on the route.
 */
function requireCronSecret(request: Request): void {
  const secret = process.env.CRON_SECRET;
  if (!secret) {
    throw new ApiError(500, "cron_not_configured", "CRON_SECRET is not set");
  }
  if (request.headers.get("authorization") !== `Bearer ${secret}`) {
    throw new ApiError(401, "unauthorized", "Bad cron secret");
  }
}

async function nudgeUser(
  settings: typeof settingsTable.$inferSelect,
  now: Date,
): Promise<Outcome> {
  const userId = settings.userId;
  if (localHour(settings, now) !== settings.checkinNotificationHour) {
    return { userId, result: "not_the_hour" };
  }

  const dayKey = todayKey(settings, now);
  if (await hasMoodFor(userId, dayKey)) {
    return { userId, result: "already_checked_in" };
  }

  const active = await db
    .select()
    .from(devices)
    .where(and(eq(devices.userId, userId), isNull(devices.revokedAt)));
  if (active.length === 0) {
    return { userId, result: "no_devices" };
  }

  // Claim the day before sending. An insert that conflicts means another run
  // (a cron retry, or a developer curling this route) already has it. Without
  // transactions on the neon-http driver this row is the only lock there is.
  const claimed = await db
    .insert(notificationLog)
    .values({ userId, dayKey, kind: KIND })
    .onConflictDoNothing()
    .returning();
  if (claimed.length === 0) {
    return { userId, result: "already_sent_today" };
  }

  const data = await gatherNudgeData(userId, settings, dayKey);
  const nudge = composeCheckinNudge(data);

  let delivered = 0;
  for (const device of active) {
    const result = await sendPush(device.deviceToken, device.environment, {
      title: nudge.title,
      body: nudge.body,
      kind: KIND,
      dayKey,
    });
    if (result.ok) {
      delivered++;
      continue;
    }
    console.error(`APNs ${result.status} for device ${device.id}: ${result.reason}`);
    if (result.unregistered) {
      await db.update(devices).set({ revokedAt: new Date() }).where(eq(devices.id, device.id));
    }
  }

  if (delivered === 0) {
    // Nothing went out, so release the claim and let the next hourly run try
    // again. Keeping a failed row would silently cost the whole day.
    await db
      .delete(notificationLog)
      .where(
        and(
          eq(notificationLog.userId, userId),
          eq(notificationLog.dayKey, dayKey),
          eq(notificationLog.kind, KIND),
        ),
      );
    return { userId, result: "send_failed", template: nudge.template };
  }

  await db
    .update(notificationLog)
    .set({ status: "sent", sentAt: new Date(), template: nudge.template })
    .where(
      and(
        eq(notificationLog.userId, userId),
        eq(notificationLog.dayKey, dayKey),
        eq(notificationLog.kind, KIND),
      ),
    );

  return { userId, result: "sent", template: nudge.template };
}

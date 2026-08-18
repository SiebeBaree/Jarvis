import { NextResponse } from "next/server";
import { and, eq, isNull } from "drizzle-orm";
import { db } from "@/db/client";
import { devices } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody } from "@/lib/http";
import { deviceRevokeSchema } from "@/lib/validation";

export const runtime = "nodejs";

/**
 * Stop sending to this device. Called on sign-out, before the session token is
 * destroyed. The token travels in the body rather than the path so it stays out
 * of request logs. Revoking an unknown or already revoked token is a no-op.
 */
export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const { deviceToken } = await parseBody(request, deviceRevokeSchema);

  await db
    .update(devices)
    .set({ revokedAt: new Date() })
    .where(
      and(
        eq(devices.userId, ctx.userId),
        eq(devices.deviceToken, deviceToken.toLowerCase()),
        isNull(devices.revokedAt),
      ),
    );

  return NextResponse.json({ ok: true });
});

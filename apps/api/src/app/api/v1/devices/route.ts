import { NextResponse } from "next/server";
import { db } from "@/db/client";
import { devices } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody } from "@/lib/http";
import { deviceRegisterSchema } from "@/lib/validation";

export const runtime = "nodejs";

/**
 * Register this device for push. The app posts on every launch, so the token is
 * the key: re-registering refreshes the row rather than adding one, and a token
 * that was revoked on sign-out comes back to life on the next sign-in.
 */
export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, deviceRegisterSchema);
  const deviceToken = body.deviceToken.toLowerCase();

  const [device] = await db
    .insert(devices)
    .values({
      userId: ctx.userId,
      deviceToken,
      platform: body.platform,
      environment: body.environment,
    })
    .onConflictDoUpdate({
      target: devices.deviceToken,
      set: {
        userId: ctx.userId,
        environment: body.environment,
        lastSeenAt: new Date(),
        revokedAt: null,
      },
    })
    .returning();

  return NextResponse.json(device);
});

import { NextResponse } from "next/server";
import { requireAuth, revokeSession } from "@/lib/auth";
import { handler } from "@/lib/http";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  await revokeSession(ctx.rawToken);
  return NextResponse.json({ ok: true });
});

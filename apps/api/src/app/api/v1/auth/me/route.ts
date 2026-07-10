import { NextResponse } from "next/server";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  return NextResponse.json({
    user: { id: ctx.userId, email: ctx.email },
    settings: ctx.settings,
  });
});

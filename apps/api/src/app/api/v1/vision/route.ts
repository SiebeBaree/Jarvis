import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { vision } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { visionPutSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const existing = await db.query.vision.findFirst({ where: eq(vision.userId, ctx.userId) });
  if (existing) {
    return NextResponse.json({ content: existing.content, updatedAt: existing.updatedAt });
  }
  const [created] = await db.insert(vision).values({ userId: ctx.userId }).returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create vision");
  return NextResponse.json({ content: created.content, updatedAt: created.updatedAt });
});

export const PUT = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, visionPutSchema);

  const [row] = await db
    .insert(vision)
    .values({ userId: ctx.userId, content: body.content })
    .onConflictDoUpdate({
      target: vision.userId,
      set: { content: body.content, updatedAt: new Date() },
    })
    .returning();
  if (!row) throw new ApiError(500, "internal_error", "Could not save vision");

  return NextResponse.json({ content: row.content, updatedAt: row.updatedAt });
});

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { habits } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const [updated] = await db
      .update(habits)
      .set({ archivedAt: new Date() })
      .where(and(eq(habits.id, id), eq(habits.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Habit not found");

    await recomputeDay(ctx.userId, ctx.settings, todayKey(ctx.settings));
    return NextResponse.json(updated);
  },
);

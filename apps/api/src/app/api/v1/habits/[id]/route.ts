import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { habits } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";
import { habitPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, habitPatchSchema);

    const existing = await db.query.habits.findFirst({
      where: and(eq(habits.id, id), eq(habits.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Habit not found");

    if (patch.targetReps !== undefined) {
      const target = patch.targetReps;
      const invalid =
        (existing.type === "daily" && target !== 1) ||
        (existing.type === "multi_daily" && (target < 2 || target > 10)) ||
        (existing.type === "weekly_frequency" && (target < 1 || target > 7));
      if (invalid) {
        throw new ApiError(400, "invalid_target", `targetReps ${target} is not valid for a ${existing.type} habit`);
      }
    }

    const { paused, ...fields } = patch;
    const set: Partial<typeof habits.$inferInsert> = { ...fields };
    if (paused === true) set.pausedAt = existing.pausedAt ?? new Date();
    if (paused === false) set.pausedAt = null;
    if (Object.keys(set).length === 0) return NextResponse.json(existing);

    const [updated] = await db
      .update(habits)
      .set(set)
      .where(and(eq(habits.id, id), eq(habits.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Habit not found");

    await recomputeDay(ctx.userId, ctx.settings, todayKey(ctx.settings));
    return NextResponse.json(updated);
  },
);

// DELETE is an archive shortcut — history (completions, scores) must survive.
export const DELETE = handler(
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
    return NextResponse.json({ ok: true });
  },
);

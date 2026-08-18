import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { workoutSessions } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { buildSessionDetail, loadSession } from "@/lib/training";
import { sessionPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 30;

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const session = await loadSession(ctx.userId, id);
    return NextResponse.json(await buildSessionDetail(ctx.userId, session));
  },
);

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, sessionPatchSchema);

    const existing = await loadSession(ctx.userId, id);

    const set: Partial<typeof workoutSessions.$inferInsert> = {};
    if (patch.title !== undefined) set.title = patch.title.trim();
    if (patch.notes !== undefined) set.notes = patch.notes;
    if (patch.dayKey !== undefined) set.dayKey = patch.dayKey;
    // Absolute, not a toggle: a replayed "finish" must not reopen the workout.
    // Finishing twice keeps the first timestamp, so the duration stays honest.
    if (patch.finished === true) set.finishedAt = existing.finishedAt ?? new Date();
    if (patch.finished === false) set.finishedAt = null;

    if (Object.keys(set).length > 0) {
      const [updated] = await db
        .update(workoutSessions)
        .set(set)
        .where(and(eq(workoutSessions.id, id), eq(workoutSessions.userId, ctx.userId)))
        .returning();
      if (!updated) throw new ApiError(404, "not_found", "Workout not found");
      return NextResponse.json(await buildSessionDetail(ctx.userId, updated));
    }

    return NextResponse.json(await buildSessionDetail(ctx.userId, existing));
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    await loadSession(ctx.userId, id);

    await db
      .delete(workoutSessions)
      .where(and(eq(workoutSessions.id, id), eq(workoutSessions.userId, ctx.userId)));
    return NextResponse.json({ ok: true });
  },
);

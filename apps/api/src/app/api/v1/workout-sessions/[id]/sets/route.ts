// Logging a set — the single most-repeated write in the app, tapped mid-set
// with a phone in one hand and usually on bad gym wifi. It therefore has to be
// replay-safe (client-chosen id) and cheap (returns just the row, not the
// whole session; the app already knows where to put it).

import { NextResponse } from "next/server";
import { and, eq, sql } from "drizzle-orm";
import { db } from "@/db/client";
import { workoutSets } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, resolveIdempotentCreate } from "@/lib/http";
import { loadExercise, loadSession, setDTO } from "@/lib/training";
import { setUpsertSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id: sessionId } = await params;
    const body = await parseBody(request, setUpsertSchema);

    const session = await loadSession(ctx.userId, sessionId);
    await loadExercise(ctx.userId, body.exerciseId);

    let setIndex = body.setIndex;
    if (setIndex === undefined) {
      // Next slot for this movement in this workout. Computed server-side so
      // two devices logging the same session cannot both claim "set 3".
      const [row] = await db
        .select({ next: sql<number>`coalesce(max(${workoutSets.setIndex}), 0) + 1` })
        .from(workoutSets)
        .where(
          and(eq(workoutSets.sessionId, sessionId), eq(workoutSets.exerciseId, body.exerciseId)),
        );
      setIndex = row?.next ?? 1;
    }

    const insert = db.insert(workoutSets).values({
      id: body.id,
      userId: ctx.userId,
      sessionId: session.id,
      exerciseId: body.exerciseId,
      setIndex,
      weightKg: body.weightKg ?? null,
      reps: body.reps ?? null,
      isWarmup: body.isWarmup ?? false,
    });

    const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();
    if (created) return NextResponse.json(setDTO(created), { status: 201 });

    const existing = await resolveIdempotentCreate(ctx.userId, "set", () =>
      db.query.workoutSets.findFirst({ where: eq(workoutSets.id, body.id!) }),
    );
    return NextResponse.json(setDTO(existing));
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id: sessionId } = await params;
    await loadSession(ctx.userId, sessionId);

    const url = new URL(request.url);
    const exerciseId = url.searchParams.get("exerciseId");
    if (!exerciseId) {
      throw new ApiError(400, "missing_exercise", "exerciseId is required");
    }

    // Drops every set of one movement from this workout — "I logged this
    // against the wrong exercise", which otherwise needs one delete per set.
    await db
      .delete(workoutSets)
      .where(
        and(
          eq(workoutSets.sessionId, sessionId),
          eq(workoutSets.exerciseId, exerciseId),
          eq(workoutSets.userId, ctx.userId),
        ),
      );
    return NextResponse.json({ ok: true });
  },
);

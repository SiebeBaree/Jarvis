// Correcting a set after the fact (mistyped weight, wrong rep count) and
// removing one. Addressed by set id rather than nested under the session so
// the app's row can patch itself without knowing its position.

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { workoutSets } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { setDTO } from "@/lib/training";
import { setPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

async function loadSet(userId: string, id: string) {
  const row = await db.query.workoutSets.findFirst({
    where: and(eq(workoutSets.id, id), eq(workoutSets.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Set not found");
  return row;
}

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, setPatchSchema);

    const existing = await loadSet(ctx.userId, id);

    const set: Partial<typeof workoutSets.$inferInsert> = {};
    if (patch.weightKg !== undefined) set.weightKg = patch.weightKg;
    if (patch.reps !== undefined) set.reps = patch.reps;
    if (patch.isWarmup !== undefined) set.isWarmup = patch.isWarmup;
    if (patch.setIndex !== undefined) set.setIndex = patch.setIndex;

    if (Object.keys(set).length === 0) return NextResponse.json(setDTO(existing));

    const [updated] = await db
      .update(workoutSets)
      .set(set)
      .where(and(eq(workoutSets.id, id), eq(workoutSets.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Set not found");
    return NextResponse.json(setDTO(updated));
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    await loadSet(ctx.userId, id);

    await db.delete(workoutSets).where(and(eq(workoutSets.id, id), eq(workoutSets.userId, ctx.userId)));
    return NextResponse.json({ ok: true });
  },
);

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { workoutRoutines } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { isUniqueViolation } from "@/lib/metrics";
import { loadRoutine, replaceRoutineExercises, routineDetail } from "@/lib/training";
import { routinePatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    return NextResponse.json(await routineDetail(ctx.userId, id));
  },
);

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, routinePatchSchema);

    const existing = await loadRoutine(ctx.userId, id);

    const set: Partial<typeof workoutRoutines.$inferInsert> = {};
    if (patch.name !== undefined) set.name = patch.name.trim();
    if (patch.emoji !== undefined) set.emoji = patch.emoji;
    if (patch.colorHex !== undefined) set.colorHex = patch.colorHex;
    if (patch.notes !== undefined) set.notes = patch.notes;
    if (patch.sortOrder !== undefined) set.sortOrder = patch.sortOrder;
    if (patch.archived === true) set.archivedAt = existing.archivedAt ?? new Date();
    if (patch.archived === false) set.archivedAt = null;

    if (Object.keys(set).length > 0) {
      set.updatedAt = new Date();
      try {
        const [updated] = await db
          .update(workoutRoutines)
          .set(set)
          .where(and(eq(workoutRoutines.id, id), eq(workoutRoutines.userId, ctx.userId)))
          .returning();
        if (!updated) throw new ApiError(404, "not_found", "Routine not found");
      } catch (err) {
        if (isUniqueViolation(err)) {
          throw new ApiError(409, "name_exists", "A routine with that name already exists");
        }
        throw err;
      }
    }

    if (patch.exercises !== undefined) {
      await replaceRoutineExercises(ctx.userId, id, patch.exercises);
    }

    return NextResponse.json(await routineDetail(ctx.userId, id));
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    await loadRoutine(ctx.userId, id);

    // Routine lines cascade; past sessions keep their rows and simply lose the
    // routine link, because a workout you did is a fact about your history.
    await db
      .delete(workoutRoutines)
      .where(and(eq(workoutRoutines.id, id), eq(workoutRoutines.userId, ctx.userId)));
    return NextResponse.json({ ok: true });
  },
);

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { exercises } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { isUniqueViolation } from "@/lib/metrics";
import { loadExercise } from "@/lib/training";
import { exercisePatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, exercisePatchSchema);

    const existing = await loadExercise(ctx.userId, id);

    const set: Partial<typeof exercises.$inferInsert> = {};
    if (patch.name !== undefined) set.name = patch.name.trim();
    if (patch.muscleGroup !== undefined) set.muscleGroup = patch.muscleGroup;
    if (patch.equipment !== undefined) set.equipment = patch.equipment;
    if (patch.isBodyweight !== undefined) set.isBodyweight = patch.isBodyweight;
    if (patch.notes !== undefined) set.notes = patch.notes;
    if (patch.archived === true) set.archivedAt = existing.archivedAt ?? new Date();
    if (patch.archived === false) set.archivedAt = null;

    if (Object.keys(set).length === 0) return NextResponse.json(existing);

    try {
      const [updated] = await db
        .update(exercises)
        .set(set)
        .where(and(eq(exercises.id, id), eq(exercises.userId, ctx.userId)))
        .returning();
      if (!updated) throw new ApiError(404, "not_found", "Exercise not found");
      return NextResponse.json(updated);
    } catch (err) {
      if (isUniqueViolation(err)) {
        throw new ApiError(409, "name_exists", "An exercise with that name already exists");
      }
      throw err;
    }
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    await loadExercise(ctx.userId, id);

    // Hard delete; routine lines and logged sets cascade. The app routes
    // "stop showing me this" to archive instead, so reaching here is an
    // explicit "erase its history too".
    await db.delete(exercises).where(and(eq(exercises.id, id), eq(exercises.userId, ctx.userId)));
    return NextResponse.json({ ok: true });
  },
);

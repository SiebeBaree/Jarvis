import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { mealPreps } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import {
  loadIngredients,
  loadMealPrep,
  mealPrepDTO,
  presignMealPhoto,
  replaceIngredients,
} from "@/lib/kitchen";
import { isUniqueViolation } from "@/lib/metrics";
import { mealPrepPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 30;

async function detail(userId: string, id: string) {
  const row = await loadMealPrep(userId, id);
  const [ingredients, photoUrl] = await Promise.all([
    loadIngredients([id]),
    presignMealPhoto(row),
  ]);
  return mealPrepDTO(row, ingredients.get(id) ?? [], photoUrl);
}

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    return NextResponse.json(await detail(ctx.userId, id));
  },
);

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, mealPrepPatchSchema);

    await loadMealPrep(ctx.userId, id);

    const set: Partial<typeof mealPreps.$inferInsert> = {};
    if (patch.name !== undefined) set.name = patch.name.trim();
    if (patch.description !== undefined) set.description = patch.description;
    if (patch.instructions !== undefined) set.instructions = patch.instructions;
    if (patch.prepMinutes !== undefined) set.prepMinutes = patch.prepMinutes;
    if (patch.portions !== undefined) set.portions = patch.portions;
    if (patch.basis !== undefined) set.basis = patch.basis;
    if (patch.calories !== undefined) set.calories = patch.calories;
    if (patch.proteinG !== undefined) set.proteinG = patch.proteinG;
    if (patch.carbsG !== undefined) set.carbsG = patch.carbsG;
    if (patch.fatG !== undefined) set.fatG = patch.fatG;
    if (patch.sortOrder !== undefined) set.sortOrder = patch.sortOrder;

    if (Object.keys(set).length > 0) {
      set.updatedAt = new Date();
      try {
        const [updated] = await db
          .update(mealPreps)
          .set(set)
          .where(and(eq(mealPreps.id, id), eq(mealPreps.userId, ctx.userId)))
          .returning();
        if (!updated) throw new ApiError(404, "not_found", "Meal prep not found");
      } catch (err) {
        if (isUniqueViolation(err)) {
          throw new ApiError(409, "name_exists", "A meal prep with that name already exists");
        }
        throw err;
      }
    }

    if (patch.ingredients !== undefined) {
      await replaceIngredients(ctx.userId, id, patch.ingredients);
    }

    return NextResponse.json(await detail(ctx.userId, id));
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const row = await loadMealPrep(ctx.userId, id);

    // Best-effort blob cleanup before the row goes; a leaked blob is better
    // than a delete that fails because storage was briefly unreachable.
    if (row.blobKey && process.env.BLOB_READ_WRITE_TOKEN) {
      try {
        const { del } = await import("@vercel/blob");
        await del(row.blobKey);
      } catch (error) {
        console.error("Meal prep blob cleanup failed (ignored):", error);
      }
    }

    await db.delete(mealPreps).where(and(eq(mealPreps.id, id), eq(mealPreps.userId, ctx.userId)));
    return NextResponse.json({ ok: true });
  },
);

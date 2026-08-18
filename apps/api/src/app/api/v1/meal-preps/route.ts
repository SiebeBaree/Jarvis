// Meal preps: the user's own cookbook of batches that work. Photos live on
// Vercel Blob (private store) and come back as short-lived presigned URLs, the
// same contract the progress photos use.

import { NextResponse } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { mealPreps } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, resolveIdempotentCreate } from "@/lib/http";
import { loadIngredients, mealPrepDTO, presignMealPhotos, replaceIngredients } from "@/lib/kitchen";
import { isUniqueViolation } from "@/lib/metrics";
import { mealPrepCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 30;

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);

  const rows = await db
    .select()
    .from(mealPreps)
    .where(eq(mealPreps.userId, ctx.userId))
    .orderBy(asc(mealPreps.sortOrder), asc(mealPreps.name))
    .limit(300);

  if (rows.length === 0) return NextResponse.json({ mealPreps: [] });

  const [ingredients, photoUrls] = await Promise.all([
    loadIngredients(rows.map((row) => row.id)),
    presignMealPhotos(rows),
  ]);

  return NextResponse.json({
    mealPreps: rows.map((row) =>
      mealPrepDTO(row, ingredients.get(row.id) ?? [], photoUrls.get(row.id) ?? null),
    ),
  });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, mealPrepCreateSchema);
  const name = body.name.trim();

  const insert = db.insert(mealPreps).values({
    id: body.id,
    userId: ctx.userId,
    name,
    description: body.description ?? null,
    instructions: body.instructions ?? null,
    prepMinutes: body.prepMinutes ?? null,
    portions: body.portions ?? 1,
    basis: body.basis ?? "total",
    calories: body.calories ?? null,
    proteinG: body.proteinG ?? null,
    carbsG: body.carbsG ?? null,
    fatG: body.fatG ?? null,
    sortOrder: body.sortOrder ?? 0,
  });

  let mealId: string;
  let status = 201;
  try {
    const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();
    if (created) {
      mealId = created.id;
    } else {
      const existing = await resolveIdempotentCreate(ctx.userId, "meal prep", () =>
        db.query.mealPreps.findFirst({ where: eq(mealPreps.id, body.id!) }),
      );
      mealId = existing.id;
      status = 200;
    }
  } catch (err) {
    if (isUniqueViolation(err)) {
      throw new ApiError(409, "name_exists", `A meal prep named "${name}" already exists`);
    }
    throw err;
  }

  if (body.ingredients) {
    await replaceIngredients(ctx.userId, mealId, body.ingredients);
  }

  const row = await db.query.mealPreps.findFirst({ where: eq(mealPreps.id, mealId) });
  if (!row) throw new ApiError(500, "internal_error", "Could not create meal prep");
  const ingredients = await loadIngredients([mealId]);

  return NextResponse.json(mealPrepDTO(row, ingredients.get(mealId) ?? [], null), { status });
});

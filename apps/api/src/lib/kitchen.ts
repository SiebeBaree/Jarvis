// Meal prep helpers: ownership loading, ingredient replacement, and the DTO
// shaping (including the presigned photo URL, same private-blob contract the
// progress photos use).

import { and, asc, eq, inArray } from "drizzle-orm";
import { db } from "@/db/client";
import { mealPrepIngredients, mealPreps } from "@/db/schema";
import { ApiError } from "./http";
import type { IngredientRow, MealPrepRow } from "./macros";

export { mealPrepDTO } from "./macros";
export type { IngredientDTO, MacrosDTO, MealPrepDTO, MealPrepRow, IngredientRow } from "./macros";

const SIGNED_URL_TTL_MS = 60 * 60 * 1000; // 1 hour

export const MAX_MEAL_PHOTO_BYTES = 4 * 1024 * 1024; // 4 MB
export const MEAL_EXTENSION_BY_TYPE: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/heic": "heic",
};

export function requireBlobToken(): void {
  if (!process.env.BLOB_READ_WRITE_TOKEN) {
    throw new ApiError(
      503,
      "blob_not_configured",
      "Photo storage is not configured: set BLOB_READ_WRITE_TOKEN (Vercel Blob) and redeploy",
    );
  }
}

export async function loadMealPrep(userId: string, id: string): Promise<MealPrepRow> {
  const row = await db.query.mealPreps.findFirst({
    where: and(eq(mealPreps.id, id), eq(mealPreps.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Meal prep not found");
  return row;
}

/**
 * Presigned GET URLs for a batch of meal preps. One signed token per response
 * (issuing is a network call), one presigned URL per photo.
 */
export async function presignMealPhotos(
  rows: readonly MealPrepRow[],
): Promise<Map<string, string>> {
  const urls = new Map<string, string>();
  const withPhotos = rows.filter((row) => row.blobKey !== null);
  if (withPhotos.length === 0) return urls;
  requireBlobToken();

  const { issueSignedToken, presignUrl } = await import("@vercel/blob");
  const token = await issueSignedToken({
    pathname: "*",
    operations: ["get"],
    validUntil: Date.now() + SIGNED_URL_TTL_MS,
  });
  await Promise.all(
    withPhotos.map(async (row) => {
      const { presignedUrl } = await presignUrl(token, {
        operation: "get",
        pathname: row.blobKey!,
        access: "private",
      });
      urls.set(row.id, presignedUrl);
    }),
  );
  return urls;
}

/** Presigned URL for a single meal prep, or null when it has no photo. */
export async function presignMealPhoto(row: MealPrepRow): Promise<string | null> {
  const urls = await presignMealPhotos([row]);
  return urls.get(row.id) ?? null;
}

export async function loadIngredients(mealPrepIds: string[]): Promise<Map<string, IngredientRow[]>> {
  const grouped = new Map<string, IngredientRow[]>();
  if (mealPrepIds.length === 0) return grouped;
  const rows = await db
    .select()
    .from(mealPrepIngredients)
    .where(inArray(mealPrepIngredients.mealPrepId, mealPrepIds))
    .orderBy(asc(mealPrepIngredients.sortOrder));
  for (const row of rows) {
    const list = grouped.get(row.mealPrepId) ?? [];
    list.push(row);
    grouped.set(row.mealPrepId, list);
  }
  return grouped;
}

/** Replaces the ingredient list wholesale — it is edited as one screen. */
export async function replaceIngredients(
  userId: string,
  mealPrepId: string,
  ingredients: { name: string; quantity?: string | null }[],
): Promise<void> {
  await db.delete(mealPrepIngredients).where(eq(mealPrepIngredients.mealPrepId, mealPrepId));
  if (ingredients.length === 0) return;
  await db.insert(mealPrepIngredients).values(
    ingredients.map((item, index) => ({
      userId,
      mealPrepId,
      name: item.name,
      quantity: item.quantity ?? null,
      sortOrder: index,
    })),
  );
}

// The meal's photo: POST the raw image bytes, DELETE removes it. One photo per
// meal prep — re-uploading replaces the old blob, so the store does not fill
// up with every attempt at photographing the same tray of rice.

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { mealPreps } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";
import {
  loadIngredients,
  loadMealPrep,
  MAX_MEAL_PHOTO_BYTES,
  MEAL_EXTENSION_BY_TYPE,
  mealPrepDTO,
  presignMealPhoto,
  requireBlobToken,
} from "@/lib/kitchen";

export const runtime = "nodejs";
export const maxDuration = 30;

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const existing = await loadMealPrep(ctx.userId, id);

    const contentType = (request.headers.get("content-type") ?? "")
      .split(";")[0]!
      .trim()
      .toLowerCase();
    const extension = MEAL_EXTENSION_BY_TYPE[contentType];
    if (!extension) {
      throw new ApiError(
        415,
        "unsupported_media_type",
        "Content-Type must be image/jpeg, image/png, or image/heic",
      );
    }

    const bytes = await request.arrayBuffer();
    if (bytes.byteLength === 0) {
      throw new ApiError(400, "empty_body", "Request body must contain the image bytes");
    }
    if (bytes.byteLength > MAX_MEAL_PHOTO_BYTES) {
      throw new ApiError(413, "payload_too_large", "Photos are capped at 4 MB");
    }

    requireBlobToken();

    const { put, del } = await import("@vercel/blob");
    const result = await put(`meals/${crypto.randomUUID()}.${extension}`, bytes, {
      access: "private",
      contentType,
      addRandomSuffix: true,
    });

    const [updated] = await db
      .update(mealPreps)
      .set({
        blobKey: result.pathname,
        blobUrl: result.url,
        contentType,
        sizeBytes: bytes.byteLength,
        updatedAt: new Date(),
      })
      .where(and(eq(mealPreps.id, id), eq(mealPreps.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Meal prep not found");

    // Drop the replaced blob only after the new one is safely recorded.
    if (existing.blobKey) {
      try {
        await del(existing.blobKey);
      } catch (error) {
        console.error("Replacing meal photo: old blob cleanup failed (ignored):", error);
      }
    }

    const [ingredients, photoUrl] = await Promise.all([
      loadIngredients([id]),
      presignMealPhoto(updated),
    ]);
    return NextResponse.json(mealPrepDTO(updated, ingredients.get(id) ?? [], photoUrl), {
      status: 201,
    });
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const existing = await loadMealPrep(ctx.userId, id);

    if (existing.blobKey && process.env.BLOB_READ_WRITE_TOKEN) {
      try {
        const { del } = await import("@vercel/blob");
        await del(existing.blobKey);
      } catch (error) {
        console.error("Meal photo blob cleanup failed (ignored):", error);
      }
    }

    const [updated] = await db
      .update(mealPreps)
      .set({
        blobKey: null,
        blobUrl: null,
        contentType: null,
        sizeBytes: null,
        updatedAt: new Date(),
      })
      .where(and(eq(mealPreps.id, id), eq(mealPreps.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Meal prep not found");

    const ingredients = await loadIngredients([id]);
    return NextResponse.json(mealPrepDTO(updated, ingredients.get(id) ?? [], null));
  },
);

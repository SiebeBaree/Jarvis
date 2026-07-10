import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { progressPhotos } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";

export const runtime = "nodejs";

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const photo = await db.query.progressPhotos.findFirst({
      where: and(eq(progressPhotos.id, id), eq(progressPhotos.userId, ctx.userId)),
    });
    if (!photo) throw new ApiError(404, "not_found", "Photo not found");

    // Best effort: an orphaned blob is preferable to a row pointing nowhere.
    try {
      const { del } = await import("@vercel/blob");
      await del(photo.blobUrl);
    } catch (err) {
      console.error(`Blob delete failed for ${photo.blobKey} (row removed anyway):`, err);
    }

    await db
      .delete(progressPhotos)
      .where(and(eq(progressPhotos.id, id), eq(progressPhotos.userId, ctx.userId)));

    return NextResponse.json({ ok: true });
  },
);

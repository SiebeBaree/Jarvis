// Weekly photo check-ins for one improvement area. POST takes raw image bytes
// (query carries dayKey); one check-in per ISO week — re-uploading within the
// same week replaces that week's photo.

import { NextResponse } from "next/server";
import { and, desc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { areaCheckins, improvementAreas } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { weekKeyFor } from "@/lib/checkins";
import { ApiError, handler, parseQuery } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { checkinUploadQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 120; // image upload to blob storage

type Params = { params: Promise<{ id: string }> };

const MAX_PHOTO_BYTES = 4 * 1024 * 1024;
const SIGNED_URL_TTL_MS = 60 * 60 * 1000;
const EXTENSION_BY_TYPE: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/heic": "heic",
};

function requireBlobToken() {
  if (!process.env.BLOB_READ_WRITE_TOKEN) {
    throw new ApiError(
      503,
      "blob_not_configured",
      "Photo storage is not configured: set BLOB_READ_WRITE_TOKEN (Vercel Blob) and redeploy",
    );
  }
}

async function loadArea(userId: string, id: string) {
  const row = await db.query.improvementAreas.findFirst({
    where: and(eq(improvementAreas.id, id), eq(improvementAreas.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Improvement area not found");
  return row;
}

function checkinDTO(row: typeof areaCheckins.$inferSelect, url: string) {
  return {
    id: row.id,
    areaId: row.areaId,
    weekKey: row.weekKey,
    dayKey: row.dayKey,
    url,
    createdAt: row.createdAt,
  };
}

export const GET = handler(async (request: Request, { params }: Params) => {
  const ctx = await requireAuth(request);
  const { id } = await params;
  await loadArea(ctx.userId, id);

  const rows = await db.query.areaCheckins.findMany({
    where: eq(areaCheckins.areaId, id),
    orderBy: [desc(areaCheckins.weekKey)],
  });
  if (rows.length === 0) return NextResponse.json({ checkins: [] });
  requireBlobToken();

  const { issueSignedToken, presignUrl } = await import("@vercel/blob");
  const token = await issueSignedToken({
    pathname: "*",
    operations: ["get"],
    validUntil: Date.now() + SIGNED_URL_TTL_MS,
  });
  const checkins = await Promise.all(
    rows.map(async (row) => {
      const { presignedUrl } = await presignUrl(token, {
        operation: "get",
        pathname: row.blobKey,
        access: "private",
      });
      return checkinDTO(row, presignedUrl);
    }),
  );
  return NextResponse.json({ checkins });
});

export const POST = handler(async (request: Request, { params }: Params) => {
  const ctx = await requireAuth(request);
  const { id } = await params;
  const area = await loadArea(ctx.userId, id);
  if (area.archivedAt) {
    throw new ApiError(409, "area_archived", "Unarchive this area before checking in");
  }

  const query = parseQuery(request, checkinUploadQuerySchema);
  const today = todayKey(ctx.settings);
  if (query.dayKey > today) {
    throw new ApiError(400, "future_day", "Cannot check in for a future day");
  }
  const weekKey = weekKeyFor(query.dayKey);

  const contentType = (request.headers.get("content-type") ?? "")
    .split(";")[0]!
    .trim()
    .toLowerCase();
  const extension = EXTENSION_BY_TYPE[contentType];
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
  if (bytes.byteLength > MAX_PHOTO_BYTES) {
    throw new ApiError(413, "payload_too_large", "Photos are capped at 4 MB");
  }

  requireBlobToken();
  const { put, del, issueSignedToken, presignUrl } = await import("@vercel/blob");
  const result = await put(`checkins/${crypto.randomUUID()}.${extension}`, bytes, {
    access: "private",
    contentType,
    addRandomSuffix: true,
  });

  const existing = await db.query.areaCheckins.findFirst({
    where: and(eq(areaCheckins.areaId, id), eq(areaCheckins.weekKey, weekKey)),
  });

  let saved: typeof areaCheckins.$inferSelect;
  if (existing) {
    // Same week: replace the photo.
    const [updated] = await db
      .update(areaCheckins)
      .set({
        dayKey: query.dayKey,
        blobKey: result.pathname,
        blobUrl: result.url,
        contentType,
        sizeBytes: bytes.byteLength,
        createdAt: new Date(),
      })
      .where(eq(areaCheckins.id, existing.id))
      .returning();
    saved = updated!;
    try {
      await del(existing.blobKey);
    } catch (error) {
      console.error("Old check-in blob cleanup failed (ignored):", error);
    }
  } else {
    const [created] = await db
      .insert(areaCheckins)
      .values({
        userId: ctx.userId,
        areaId: id,
        weekKey,
        dayKey: query.dayKey,
        blobKey: result.pathname,
        blobUrl: result.url,
        contentType,
        sizeBytes: bytes.byteLength,
      })
      .returning();
    if (!created) throw new ApiError(500, "internal_error", "Could not save check-in");
    saved = created;
  }

  const token = await issueSignedToken({
    pathname: saved.blobKey,
    operations: ["get"],
    validUntil: Date.now() + SIGNED_URL_TTL_MS,
  });
  const { presignedUrl } = await presignUrl(token, {
    operation: "get",
    pathname: saved.blobKey,
    access: "private",
  });
  return NextResponse.json(checkinDTO(saved, presignedUrl), { status: 201 });
});

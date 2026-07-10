// Progress photos on Vercel Blob (PRIVATE store). POST takes the raw image
// bytes (query params carry angle + dayKey). GET returns short-lived presigned
// URLs: one signed token per response, one presigned URL per photo.
// Verified live 2026-07-10: put(access private) → issueSignedToken → presignUrl → 200.

import { NextResponse } from "next/server";
import { and, desc, eq, gte, lte, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { progressPhotos } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseQuery } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { photosQuerySchema, photoUploadQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

const MAX_PHOTO_BYTES = 4 * 1024 * 1024; // 4 MB
const SIGNED_URL_TTL_MS = 60 * 60 * 1000; // 1 hour
const EXTENSION_BY_TYPE: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/heic": "heic",
};
const PHOTO_LIST_CAP = 500;

function requireBlobToken() {
  if (!process.env.BLOB_READ_WRITE_TOKEN) {
    throw new ApiError(
      503,
      "blob_not_configured",
      "Photo storage is not configured: set BLOB_READ_WRITE_TOKEN (Vercel Blob) and redeploy",
    );
  }
}

function photoDTO(row: typeof progressPhotos.$inferSelect, url: string) {
  return {
    id: row.id,
    dayKey: row.dayKey,
    angle: row.angle,
    url,
    contentType: row.contentType,
    sizeBytes: row.sizeBytes,
    createdAt: row.createdAt,
  };
}

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, photosQuerySchema);

  const conditions: SQL[] = [eq(progressPhotos.userId, ctx.userId)];
  if (query.from) conditions.push(gte(progressPhotos.dayKey, query.from));
  if (query.to) conditions.push(lte(progressPhotos.dayKey, query.to));

  const rows = await db.query.progressPhotos.findMany({
    where: and(...conditions),
    orderBy: [desc(progressPhotos.dayKey), desc(progressPhotos.createdAt)],
    limit: PHOTO_LIST_CAP,
  });

  if (rows.length === 0) return NextResponse.json({ photos: [] });
  requireBlobToken();

  // One store-wide read token for this response; per-photo presigned URLs.
  const { issueSignedToken, presignUrl } = await import("@vercel/blob");
  const token = await issueSignedToken({
    pathname: "*",
    operations: ["get"],
    validUntil: Date.now() + SIGNED_URL_TTL_MS,
  });
  const photos = await Promise.all(
    rows.map(async (row) => {
      const { presignedUrl } = await presignUrl(token, {
        operation: "get",
        pathname: row.blobKey,
        access: "private",
      });
      return photoDTO(row, presignedUrl);
    }),
  );

  return NextResponse.json({ photos });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, photoUploadQuerySchema);
  if (query.dayKey > todayKey(ctx.settings)) {
    throw new ApiError(400, "future_day", "Cannot add a photo for a future day");
  }

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

  const { put, issueSignedToken, presignUrl } = await import("@vercel/blob");
  const result = await put(`photos/${crypto.randomUUID()}.${extension}`, bytes, {
    access: "private",
    contentType,
    addRandomSuffix: true,
  });

  const [created] = await db
    .insert(progressPhotos)
    .values({
      userId: ctx.userId,
      blobKey: result.pathname,
      blobUrl: result.url,
      angle: query.angle,
      dayKey: query.dayKey,
      contentType,
      sizeBytes: bytes.byteLength,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not save photo");

  // Return a fetchable URL so the app can render the thumbnail immediately.
  const token = await issueSignedToken({
    pathname: created.blobKey,
    operations: ["get"],
    validUntil: Date.now() + SIGNED_URL_TTL_MS,
  });
  const { presignedUrl } = await presignUrl(token, {
    operation: "get",
    pathname: created.blobKey,
    access: "private",
  });
  return NextResponse.json(photoDTO(created, presignedUrl), { status: 201 });
});

import { NextResponse } from "next/server";
import { and, desc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { areaCheckins, improvementAreas } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { buildAreaDTO, weekKeyFor } from "@/lib/checkins";
import { ApiError, handler, parseBody } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { improvementAreaPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

type Params = { params: Promise<{ id: string }> };

async function loadArea(userId: string, id: string) {
  const row = await db.query.improvementAreas.findFirst({
    where: and(eq(improvementAreas.id, id), eq(improvementAreas.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Improvement area not found");
  return row;
}

export const PATCH = handler(async (request: Request, { params }: Params) => {
  const ctx = await requireAuth(request);
  const { id } = await params;
  const body = await parseBody(request, improvementAreaPatchSchema);
  await loadArea(ctx.userId, id);

  const [updated] = await db
    .update(improvementAreas)
    .set({
      ...(body.name !== undefined ? { name: body.name } : {}),
      ...(body.emoji !== undefined ? { emoji: body.emoji } : {}),
      ...(body.betterLooksLike !== undefined ? { betterLooksLike: body.betterLooksLike } : {}),
      ...(body.sortOrder !== undefined ? { sortOrder: body.sortOrder } : {}),
      ...(body.archived !== undefined ? { archivedAt: body.archived ? new Date() : null } : {}),
    })
    .where(eq(improvementAreas.id, id))
    .returning();

  const latest = await db.query.areaCheckins.findFirst({
    where: eq(areaCheckins.areaId, id),
    orderBy: [desc(areaCheckins.weekKey)],
  });
  return NextResponse.json(
    buildAreaDTO(updated!, latest ?? null, weekKeyFor(todayKey(ctx.settings))),
  );
});

export const DELETE = handler(async (request: Request, { params }: Params) => {
  const ctx = await requireAuth(request);
  const { id } = await params;
  await loadArea(ctx.userId, id);

  // Best-effort blob cleanup before the rows cascade away.
  const checkins = await db.query.areaCheckins.findMany({
    where: eq(areaCheckins.areaId, id),
    columns: { blobKey: true },
  });
  if (checkins.length > 0 && process.env.BLOB_READ_WRITE_TOKEN) {
    try {
      const { del } = await import("@vercel/blob");
      await del(checkins.map((c) => c.blobKey));
    } catch (error) {
      console.error("Blob cleanup failed (ignored):", error);
    }
  }

  await db.delete(improvementAreas).where(eq(improvementAreas.id, id));
  return NextResponse.json({ ok: true });
});

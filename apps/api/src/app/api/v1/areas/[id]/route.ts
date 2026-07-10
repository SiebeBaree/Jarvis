import { NextResponse } from "next/server";
import { and, eq, ne } from "drizzle-orm";
import { db } from "@/db/client";
import { areas } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { areaPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, areaPatchSchema);

    const existing = await db.query.areas.findFirst({
      where: and(eq(areas.id, id), eq(areas.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Area not found");

    if (patch.name !== undefined) {
      const duplicate = await db.query.areas.findFirst({
        where: and(eq(areas.userId, ctx.userId), eq(areas.name, patch.name), ne(areas.id, id)),
      });
      if (duplicate) {
        throw new ApiError(409, "name_exists", "An area with that name already exists");
      }
    }

    const { archived, ...fields } = patch;
    const set: Partial<typeof areas.$inferInsert> = { ...fields };
    if (archived === true) set.archivedAt = existing.archivedAt ?? new Date();
    if (archived === false) set.archivedAt = null;
    if (Object.keys(set).length === 0) return NextResponse.json(existing);

    const [updated] = await db
      .update(areas)
      .set(set)
      .where(and(eq(areas.id, id), eq(areas.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Area not found");

    return NextResponse.json(updated);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const [deleted] = await db
      .delete(areas)
      .where(and(eq(areas.id, id), eq(areas.userId, ctx.userId)))
      .returning();
    if (!deleted) throw new ApiError(404, "not_found", "Area not found");

    return NextResponse.json({ ok: true });
  },
);

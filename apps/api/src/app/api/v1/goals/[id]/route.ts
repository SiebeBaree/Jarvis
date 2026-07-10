import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks, goals } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { goalPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, goalPatchSchema);

    if (patch.blockId) {
      const block = await db.query.blocks.findFirst({
        where: and(eq(blocks.id, patch.blockId), eq(blocks.userId, ctx.userId)),
      });
      if (!block) throw new ApiError(404, "not_found", "Block not found");
    }

    if (Object.keys(patch).length === 0) {
      const existing = await db.query.goals.findFirst({
        where: and(eq(goals.id, id), eq(goals.userId, ctx.userId)),
      });
      if (!existing) throw new ApiError(404, "not_found", "Goal not found");
      return NextResponse.json(existing);
    }

    const [updated] = await db
      .update(goals)
      .set(patch)
      .where(and(eq(goals.id, id), eq(goals.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Goal not found");

    return NextResponse.json(updated);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const [deleted] = await db
      .delete(goals)
      .where(and(eq(goals.id, id), eq(goals.userId, ctx.userId)))
      .returning();
    if (!deleted) throw new ApiError(404, "not_found", "Goal not found");

    return NextResponse.json({ ok: true });
  },
);

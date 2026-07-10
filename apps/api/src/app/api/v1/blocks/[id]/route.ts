import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { blockPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, blockPatchSchema);

    if (patch.title === undefined) {
      const existing = await db.query.blocks.findFirst({
        where: and(eq(blocks.id, id), eq(blocks.userId, ctx.userId)),
      });
      if (!existing) throw new ApiError(404, "not_found", "Block not found");
      return NextResponse.json(existing);
    }

    const [updated] = await db
      .update(blocks)
      .set({ title: patch.title })
      .where(and(eq(blocks.id, id), eq(blocks.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Block not found");

    return NextResponse.json(updated);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const block = await db.query.blocks.findFirst({
      where: and(eq(blocks.id, id), eq(blocks.userId, ctx.userId)),
    });
    if (!block) throw new ApiError(404, "not_found", "Block not found");
    if (block.status === "active") {
      throw new ApiError(409, "block_active", "An active block cannot be deleted");
    }

    await db.delete(blocks).where(eq(blocks.id, block.id));
    return NextResponse.json({ ok: true });
  },
);

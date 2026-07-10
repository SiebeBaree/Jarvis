import { NextResponse } from "next/server";
import { and, eq, ne } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const block = await db.query.blocks.findFirst({
      where: and(eq(blocks.id, id), eq(blocks.userId, ctx.userId)),
    });
    if (!block) throw new ApiError(404, "not_found", "Block not found");

    const today = todayKey(ctx.settings);
    if (today > block.endDate) {
      throw new ApiError(400, "block_ended", "This block has already ended");
    }
    if (block.status === "active") return NextResponse.json(block);

    // Invariant: at most one active block — any other active one is done.
    await db
      .update(blocks)
      .set({ status: "completed" })
      .where(
        and(eq(blocks.userId, ctx.userId), eq(blocks.status, "active"), ne(blocks.id, block.id)),
      );

    const [updated] = await db
      .update(blocks)
      .set({ status: "active" })
      .where(eq(blocks.id, block.id))
      .returning();
    if (!updated) throw new ApiError(500, "internal_error", "Could not activate block");

    return NextResponse.json(updated);
  },
);

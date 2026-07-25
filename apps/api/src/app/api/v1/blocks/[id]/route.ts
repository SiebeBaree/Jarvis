import { NextResponse } from "next/server";
import { and, asc, eq, gte, lte, or } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks, dailyScores } from "@/db/schema";
import { requireAuth, type AuthContext } from "@/lib/auth";
import {
  assertNoBlockOverlap,
  blockStatusForRange,
  BLOCK_LENGTH_DAYS,
  snapToMonday,
  type BlockRow,
} from "@/lib/blocks";
import { addDays, type DayKey } from "@/lib/daykey";
import { ApiError, handler, parseBody } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";
import { blockPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 60; // moving a block can rescore both date ranges

/** Two block ranges span 182 days at most; the cap only guards the pathological. */
const MAX_RESCORED_DAYS = 200;

/**
 * daily_scores rows carry an isReviewWeek flag derived from the block range,
 * so moving a block invalidates the days it left and the days it now covers.
 * Only days that already have a row are touched — the rest are computed lazily.
 */
async function rescoreMovedRanges(ctx: AuthContext, before: BlockRow, after: BlockRow): Promise<void> {
  const stale = await db.query.dailyScores.findMany({
    where: and(
      eq(dailyScores.userId, ctx.userId),
      or(
        and(gte(dailyScores.dayKey, before.startDate), lte(dailyScores.dayKey, before.endDate)),
        and(gte(dailyScores.dayKey, after.startDate), lte(dailyScores.dayKey, after.endDate)),
      ),
    ),
    columns: { dayKey: true },
    orderBy: [asc(dailyScores.dayKey)],
    limit: MAX_RESCORED_DAYS,
  });
  for (const row of stale) {
    await recomputeDay(ctx.userId, ctx.settings, row.dayKey);
  }
}

/** Re-place a block on the calendar: snap, re-check overlap, re-derive status. */
async function moveBlock(ctx: AuthContext, id: string, start: DayKey, title: string | undefined) {
  const existing = await db.query.blocks.findMany({ where: eq(blocks.userId, ctx.userId) });
  const block = existing.find((b) => b.id === id);
  if (!block) throw new ApiError(404, "not_found", "Block not found");

  const startDate = snapToMonday(start);
  const endDate = addDays(startDate, BLOCK_LENGTH_DAYS);
  assertNoBlockOverlap(existing, startDate, endDate, id);

  const status = blockStatusForRange(
    { startDate, endDate },
    todayKey(ctx.settings),
    existing.some((b) => b.id !== id && b.status === "active"),
  );

  const [updated] = await db
    .update(blocks)
    .set({ ...(title === undefined ? {} : { title }), startDate, endDate, status })
    .where(and(eq(blocks.id, id), eq(blocks.userId, ctx.userId)))
    .returning();
  if (!updated) throw new ApiError(404, "not_found", "Block not found");

  await rescoreMovedRanges(ctx, block, updated);
  return NextResponse.json(updated);
}

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, blockPatchSchema);

    if (patch.startDate !== undefined) return moveBlock(ctx, id, patch.startDate, patch.title);

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

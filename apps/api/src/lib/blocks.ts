// Shared 12-Week-Year block helpers: Monday snapping, the pre-insert
// invariants (no overlap, at most one active block, lifetime numbering),
// and per-week score averages over a block.

import { and, eq, gte, lte } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks, dailyScores } from "@/db/schema";
import { addDays, isoWeekday, weekIndexInBlock, type DayKey } from "./daykey";
import { ApiError } from "./http";

/** 12 execution weeks + 1 review week. */
export const WEEKS_IN_BLOCK = 13;

/** Blocks span 13 weeks: 12 execution weeks + 1 review week. */
export const BLOCK_LENGTH_DAYS = WEEKS_IN_BLOCK * 7 - 1;

export type BlockRow = typeof blocks.$inferSelect;

/** Next Monday on/after the given dayKey. */
export function snapToMonday(dayKey: DayKey): DayKey {
  const weekday = isoWeekday(dayKey);
  return weekday === 1 ? dayKey : addDays(dayKey, 8 - weekday);
}

export type BlockRangeInput = Pick<BlockRow, "id" | "title" | "startDate" | "endDate">;

/**
 * Throws 409 when [startDate, endDate] overlaps one of the user's blocks.
 * `excludeId` skips the block being moved, which always overlaps itself.
 */
export function assertNoBlockOverlap(
  existing: BlockRangeInput[],
  startDate: DayKey,
  endDate: DayKey,
  excludeId?: string,
): void {
  const overlapping = existing.find(
    (b) => b.id !== excludeId && b.startDate <= endDate && b.endDate >= startDate,
  );
  if (overlapping) {
    throw new ApiError(409, "block_overlap", `Overlaps existing block "${overlapping.title}"`);
  }
}

/**
 * Status a block should carry for a given range: past → completed, future →
 * planned, covering today → active unless another block already holds the
 * single active slot. Used when a block's dates move.
 */
export function blockStatusForRange(
  range: Pick<BlockRow, "startDate" | "endDate">,
  today: DayKey,
  otherIsActive: boolean,
): BlockRow["status"] {
  if (range.endDate < today) return "completed";
  if (range.startDate > today) return "planned";
  return otherIsActive ? "planned" : "active";
}

/**
 * Pre-insert checks for a new block: throws 409 when [startDate, endDate]
 * overlaps an existing block; returns whether another block is currently
 * active and the next lifetime block number.
 */
export async function prepareBlockSlot(
  userId: string,
  startDate: DayKey,
  endDate: DayKey,
): Promise<{ hasActive: boolean; nextNumber: number }> {
  const existing = await db.query.blocks.findMany({ where: eq(blocks.userId, userId) });
  assertNoBlockOverlap(existing, startDate, endDate);
  const hasActive = existing.some((b) => b.status === "active");
  const maxNumber = existing.reduce((maxN, b) => Math.max(maxN, b.number), 0);
  return { hasActive, nextNumber: maxNumber + 1 };
}

export type BlockStatusInput = Pick<BlockRow, "id" | "status" | "startDate" | "endDate">;

/**
 * Pure status-transition logic for {@link reconcileBlockStatuses}:
 * (a) active blocks whose endDate is in the past → completed;
 * (b) if no active block covers today afterwards, a planned block whose
 *     [startDate, endDate] covers today → active.
 * Returns the id → new status map (empty when nothing changes).
 */
export function blockStatusTransitions(
  allBlocks: BlockStatusInput[],
  today: DayKey,
): Map<string, "completed" | "active"> {
  const transitions = new Map<string, "completed" | "active">();
  for (const block of allBlocks) {
    if (block.status === "active" && block.endDate < today) transitions.set(block.id, "completed");
  }
  const hasActiveCoveringToday = allBlocks.some(
    (b) =>
      b.status === "active" &&
      !transitions.has(b.id) &&
      b.startDate <= today &&
      b.endDate >= today,
  );
  if (!hasActiveCoveringToday) {
    const candidate = allBlocks.find(
      (b) => b.status === "planned" && b.startDate <= today && b.endDate >= today,
    );
    if (candidate) transitions.set(candidate.id, "active");
  }
  return transitions;
}

/**
 * Complete ended active blocks and activate the planned block whose start
 * has arrived. Called lazily from the Today payload so the world stays
 * consistent without a cron.
 */
export async function reconcileBlockStatuses(userId: string, today: DayKey): Promise<void> {
  const existing = await db.query.blocks.findMany({ where: eq(blocks.userId, userId) });
  const transitions = blockStatusTransitions(existing, today);
  for (const [id, status] of transitions) {
    await db.update(blocks).set({ status }).where(eq(blocks.id, id));
  }
}

export interface WeekScoreAverage {
  weekNumber: number; // 1..13
  avg: number | null; // avg of non-null daily totals, 2 decimals; null = no data
  from: DayKey;
  to: DayKey;
}

/**
 * Average daily_scores.total per block week (1..13). One query over the
 * block's date range, grouped into weeks here.
 */
export async function weeklyScoreAverages(
  userId: string,
  block: Pick<BlockRow, "startDate" | "endDate">,
): Promise<WeekScoreAverage[]> {
  const rows = await db.query.dailyScores.findMany({
    where: and(
      eq(dailyScores.userId, userId),
      gte(dailyScores.dayKey, block.startDate),
      lte(dailyScores.dayKey, block.endDate),
    ),
    columns: { dayKey: true, total: true },
  });

  const totalsByWeek = new Map<number, number[]>();
  for (const row of rows) {
    if (row.total === null) continue;
    const week = weekIndexInBlock(row.dayKey, block.startDate);
    const list = totalsByWeek.get(week);
    if (list) list.push(row.total);
    else totalsByWeek.set(week, [row.total]);
  }

  return Array.from({ length: WEEKS_IN_BLOCK }, (_, i) => {
    const totals = totalsByWeek.get(i + 1) ?? [];
    const avg =
      totals.length === 0
        ? null
        : Math.round((totals.reduce((sum, t) => sum + t, 0) / totals.length) * 100) / 100;
    const from = addDays(block.startDate, i * 7);
    return { weekNumber: i + 1, avg, from, to: addDays(from, 6) };
  });
}

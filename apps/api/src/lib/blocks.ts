// Shared 12-Week-Year block helpers: Monday snapping and the pre-insert
// invariants (no overlap, at most one active block, lifetime numbering).

import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks } from "@/db/schema";
import { addDays, isoWeekday, type DayKey } from "./daykey";
import { ApiError } from "./http";

/** Blocks span 13 weeks: 12 execution weeks + 1 review week. */
export const BLOCK_LENGTH_DAYS = 13 * 7 - 1;

export type BlockRow = typeof blocks.$inferSelect;

/** Next Monday on/after the given dayKey. */
export function snapToMonday(dayKey: DayKey): DayKey {
  const weekday = isoWeekday(dayKey);
  return weekday === 1 ? dayKey : addDays(dayKey, 8 - weekday);
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
  const overlapping = existing.find((b) => b.startDate <= endDate && b.endDate >= startDate);
  if (overlapping) {
    throw new ApiError(409, "block_overlap", `Overlaps existing block "${overlapping.title}"`);
  }
  const hasActive = existing.some((b) => b.status === "active");
  const maxNumber = existing.reduce((maxN, b) => Math.max(maxN, b.number), 0);
  return { hasActive, nextNumber: maxNumber + 1 };
}

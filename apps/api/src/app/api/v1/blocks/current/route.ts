// The Plan-tab payload: the block covering today (or the soonest upcoming one),
// week position, per-week score averages, and this block's goals with tactics
// and computed progress.

import { NextResponse } from "next/server";
import { and, asc, eq, gt, inArray } from "drizzle-orm";
import { db } from "@/db/client";
import { areas, blocks, goals, tactics } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { weeklyScoreAverages } from "@/lib/blocks";
import { isReviewWeek as isReviewWeekFn, weekIndexInBlock } from "@/lib/daykey";
import { handler } from "@/lib/http";
import { activeBlockFor, todayKey } from "@/lib/scoring/snapshot";
import { completedWeeksByTactic, type TacticRow } from "@/lib/tactics";

export const runtime = "nodejs";

type TacticWithWeeks = TacticRow & { completedWeeks: number[] };

/**
 * manualProgress wins when set; otherwise completed tactic-weeks over
 * applicable tactic-weeks (each tactic counts fromWeek..min(toWeek, currentWeek)).
 * Null when there is nothing to measure yet.
 */
function goalProgress(
  manualProgress: number | null,
  goalTactics: TacticWithWeeks[],
  currentWeek: number | null,
): number | null {
  if (manualProgress !== null) return manualProgress / 100;
  if (currentWeek === null || goalTactics.length === 0) return null;

  let applicable = 0;
  let completed = 0;
  for (const tactic of goalTactics) {
    const lastWeek = Math.min(tactic.toWeek, currentWeek);
    if (lastWeek < tactic.fromWeek) continue;
    applicable += lastWeek - tactic.fromWeek + 1;
    completed += tactic.completedWeeks.filter(
      (w) => w >= tactic.fromWeek && w <= lastWeek,
    ).length;
  }
  if (applicable === 0) return null;
  return Math.min(1, completed / applicable);
}

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const today = todayKey(ctx.settings);

  // Strictly the active block containing today; else the soonest future block.
  let block = await activeBlockFor(ctx.userId, today);
  let isUpcoming = false;
  if (!block) {
    block = await db.query.blocks.findFirst({
      where: and(
        eq(blocks.userId, ctx.userId),
        inArray(blocks.status, ["active", "planned"]),
        gt(blocks.startDate, today),
      ),
      orderBy: [asc(blocks.startDate)],
    });
    isUpcoming = Boolean(block);
  }

  if (!block) {
    return NextResponse.json({
      block: null,
      isUpcoming: false,
      weekNumber: null,
      isReviewWeek: false,
      weekScores: [],
      goals: [],
    });
  }

  const weekNumber = isUpcoming ? null : weekIndexInBlock(today, block.startDate);
  const reviewWeek = isUpcoming ? false : isReviewWeekFn(today, block.startDate, block.endDate);

  // Shared week-avg computation; this payload keeps only {weekNumber, avg}.
  const weekScores = (await weeklyScoreAverages(ctx.userId, block)).map(
    ({ weekNumber: n, avg }) => ({ weekNumber: n, avg }),
  );

  // Goals of THIS block, with their area and tactics.
  const goalRows = await db
    .select({ goal: goals, areaName: areas.name, areaEmoji: areas.emoji })
    .from(goals)
    .leftJoin(areas, eq(goals.areaId, areas.id))
    .where(and(eq(goals.userId, ctx.userId), eq(goals.blockId, block.id)))
    .orderBy(asc(goals.sortOrder), asc(goals.createdAt));

  const goalIds = goalRows.map((r) => r.goal.id);
  const tacticRows =
    goalIds.length === 0
      ? []
      : await db.query.tactics.findMany({
          where: inArray(tactics.goalId, goalIds),
          orderBy: [asc(tactics.sortOrder), asc(tactics.createdAt)],
        });
  const completions = await completedWeeksByTactic(tacticRows.map((t) => t.id));

  const goalsPayload = goalRows.map(({ goal, areaName, areaEmoji }) => {
    const goalTactics: TacticWithWeeks[] = tacticRows
      .filter((t) => t.goalId === goal.id)
      .map((t) => ({ ...t, completedWeeks: completions.get(t.id) ?? [] }));
    return {
      ...goal,
      areaName,
      areaEmoji,
      progress: goalProgress(goal.manualProgress, goalTactics, weekNumber),
      tactics: goalTactics,
    };
  });

  return NextResponse.json({
    block,
    isUpcoming,
    weekNumber,
    isReviewWeek: reviewWeek,
    weekScores,
    goals: goalsPayload,
  });
});

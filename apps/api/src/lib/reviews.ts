// Seeds review conversations with computed stats + the review protocol.
// The chat agent loop passes the returned block as extraInstructions, so a
// weekly_review / block_review conversation runs through the SAME agent
// (tools included — adjustments become confirmable action cards).

import { and, eq, gte, inArray, lte } from "drizzle-orm";
import { db } from "@/db/client";
import {
  blocks,
  conversations,
  dailyScores,
  goals,
  tacticCompletions,
  tactics,
} from "@/db/schema";
import type { SettingsRow } from "./auth";
import { weeklyScoreAverages } from "./blocks";
import { addDays, type DayKey } from "./daykey";
import { applicableHabits, repCounts } from "./scoring/snapshot";

export type ConversationRow = typeof conversations.$inferSelect;

/** Per-habit reps vs target over [from, to] (one week or a whole block). */
async function habitResults(
  userId: string,
  settings: SettingsRow,
  from: DayKey,
  to: DayKey,
  weeksSpanned: number,
): Promise<{ name: string; type: string; reps: number; target: number; met: boolean }[]> {
  const [habitRows, reps] = await Promise.all([
    applicableHabits(userId, to, settings),
    repCounts(userId, from, to),
  ]);
  return habitRows.map((habit) => {
    let total = 0;
    for (const count of (reps.get(habit.id) ?? new Map<DayKey, number>()).values()) {
      total += count;
    }
    const perWeek = habit.type === "weekly_frequency" ? habit.targetReps : habit.targetReps * 7;
    const target = perWeek * weeksSpanned;
    return { name: habit.name, type: habit.type, reps: total, target, met: total >= target };
  });
}

async function loadBlockGoals(userId: string, blockId: string) {
  return db.query.goals.findMany({
    where: and(eq(goals.userId, userId), eq(goals.blockId, blockId)),
  });
}

async function weeklySeed(conversation: ConversationRow, settings: SettingsRow): Promise<string> {
  if (!conversation.blockId || !conversation.weekNumber) return "";
  const block = await db.query.blocks.findFirst({
    where: and(eq(blocks.id, conversation.blockId), eq(blocks.userId, conversation.userId)),
  });
  if (!block) return "";

  const weekNumber = conversation.weekNumber;
  const from = addDays(block.startDate, (weekNumber - 1) * 7);
  const to = addDays(from, 6);

  const [scoreRows, habits, blockGoals] = await Promise.all([
    db.query.dailyScores.findMany({
      where: and(
        eq(dailyScores.userId, conversation.userId),
        gte(dailyScores.dayKey, from),
        lte(dailyScores.dayKey, to),
      ),
      columns: { dayKey: true, total: true },
    }),
    habitResults(conversation.userId, settings, from, to, 1),
    loadBlockGoals(conversation.userId, conversation.blockId),
  ]);

  const goalIds = blockGoals.map((g) => g.id);
  const tacticRows =
    goalIds.length === 0
      ? []
      : await db.query.tactics.findMany({ where: inArray(tactics.goalId, goalIds) });
  const weekTactics = tacticRows.filter(
    (t) => t.fromWeek <= weekNumber && weekNumber <= t.toWeek,
  );
  const completedTacticIds = new Set(
    weekTactics.length === 0
      ? []
      : (
          await db.query.tacticCompletions.findMany({
            where: and(
              inArray(tacticCompletions.tacticId, weekTactics.map((t) => t.id)),
              eq(tacticCompletions.weekNumber, weekNumber),
            ),
          })
        ).map((row) => row.tacticId),
  );
  const goalTitleById = new Map(blockGoals.map((g) => [g.id, g.title]));

  const stats = {
    week: { number: weekNumber, from, to },
    dayScores: scoreRows
      .sort((a, b) => (a.dayKey < b.dayKey ? -1 : 1))
      .map((r) => ({ dayKey: r.dayKey, total: r.total })),
    habits,
    tactics: weekTactics.map((t) => ({
      title: t.title,
      goal: goalTitleById.get(t.goalId) ?? null,
      completedThisWeek: completedTacticIds.has(t.id),
    })),
    goals: blockGoals.map((g) => ({
      title: g.title,
      status: g.status,
      trackStatus: g.trackStatus,
      manualProgress: g.manualProgress,
    })),
  };

  return `## WEEKLY REVIEW MODE
You are running the WEEKLY REVIEW for week ${weekNumber} of block ${block.number} "${block.title}" (${from} → ${to}). This conversation is the review — stay on it.

Computed week stats (trustworthy; do not re-query these):
${JSON.stringify(stats)}

Protocol, in order:
1. Open by walking through what the stats show — at most 2-3 concrete observations (numbers, not vibes). No padding.
2. Ask 3-5 reflective questions, ONE AT A TIME — exactly one question per message, then wait. Each question must be concrete, literal, and unambiguous (autism-friendly); anchor every question to something specific in the stats.
3. After the questions, propose next-week adjustments through your mutating tools — habit targets, tasks/templates, goal track status. Each proposal becomes a card the user confirms in the app.
4. Keep the entire review under ~8 exchanges. End with a 2-3 sentence summary and tell the user they can close the review in the app.`;
}

async function blockSeed(conversation: ConversationRow, settings: SettingsRow): Promise<string> {
  if (!conversation.blockId) return "";
  const block = await db.query.blocks.findFirst({
    where: and(eq(blocks.id, conversation.blockId), eq(blocks.userId, conversation.userId)),
  });
  if (!block) return "";

  const executionEnd = addDays(block.startDate, 12 * 7 - 1); // weeks 1-12
  const [weeks, habits, blockGoals] = await Promise.all([
    weeklyScoreAverages(conversation.userId, block),
    habitResults(conversation.userId, settings, block.startDate, executionEnd, 12),
    loadBlockGoals(conversation.userId, conversation.blockId),
  ]);

  const stats = {
    block: {
      number: block.number,
      title: block.title,
      startDate: block.startDate,
      endDate: block.endDate,
    },
    weeklyScoreTrend: weeks
      .filter((w) => w.weekNumber <= 12)
      .map((w) => ({ weekNumber: w.weekNumber, avg: w.avg })),
    goals: blockGoals.map((g) => ({
      title: g.title,
      status: g.status,
      trackStatus: g.trackStatus,
      manualProgress: g.manualProgress,
    })),
    habitTotals: habits,
  };

  return `## BLOCK RETROSPECTIVE MODE
You are running the BLOCK RETROSPECTIVE for block ${block.number} "${block.title}" (${block.startDate} → ${block.endDate}). This conversation is the retrospective — stay on it.

Computed block stats (trustworthy; do not re-query these):
${JSON.stringify(stats)}

Protocol, in order:
1. Open with the 12-week picture — 2-3 concrete observations from the weekly score trend and goal outcomes.
2. Run a retrospective conversation: for each goal, ask what actually happened and whether to keep, change, or drop it next block. One question per message; concrete and literal.
3. Cover habits briefly: which earned their place, which to retire.
4. Do NOT create the next block or its goals here. When the retrospective is done, remind the user to run re-onboarding from the Plan tab — that flow designs the next block. End with a short summary and tell them they can close the retrospective in the app.`;
}

/**
 * Instruction block seeding a review conversation, appended to the agent's
 * system context on every turn. Empty string for plain chats.
 */
export async function buildReviewSeed(
  conversation: ConversationRow,
  settings: SettingsRow,
): Promise<string> {
  switch (conversation.kind) {
    case "weekly_review":
      return weeklySeed(conversation, settings);
    case "block_review":
      return blockSeed(conversation, settings);
    default:
      return "";
  }
}

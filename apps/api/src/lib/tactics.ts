// Shared tactic helpers: ownership loading and completed-week lookups.

import { and, asc, eq, inArray } from "drizzle-orm";
import { db } from "@/db/client";
import { tacticCompletions, tactics } from "@/db/schema";
import { ApiError } from "./http";

export type TacticRow = typeof tactics.$inferSelect;

/** Loads a tactic scoped to the user. Throws 404. */
export async function loadTactic(userId: string, id: string): Promise<TacticRow> {
  const tactic = await db.query.tactics.findFirst({
    where: and(eq(tactics.id, id), eq(tactics.userId, userId)),
  });
  if (!tactic) throw new ApiError(404, "not_found", "Tactic not found");
  return tactic;
}

/** completedWeeks (sorted ascending) for each of the given tactic ids. */
export async function completedWeeksByTactic(
  tacticIds: string[],
): Promise<Map<string, number[]>> {
  const map = new Map<string, number[]>();
  if (tacticIds.length === 0) return map;
  const rows = await db.query.tacticCompletions.findMany({
    where: inArray(tacticCompletions.tacticId, tacticIds),
    orderBy: [asc(tacticCompletions.weekNumber)],
  });
  for (const row of rows) {
    const list = map.get(row.tacticId);
    if (list) list.push(row.weekNumber);
    else map.set(row.tacticId, [row.weekNumber]);
  }
  return map;
}

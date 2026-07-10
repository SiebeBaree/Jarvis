import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { tacticCompletions } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { completedWeeksByTactic, loadTactic } from "@/lib/tactics";
import { tacticWeekPutSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PUT = handler(
  async (
    request: Request,
    { params }: { params: Promise<{ id: string; weekNumber: string }> },
  ) => {
    const ctx = await requireAuth(request);
    const { id, weekNumber: weekParam } = await params;

    const weekNumber = Number(weekParam);
    if (!Number.isInteger(weekNumber) || weekNumber < 1 || weekNumber > 12) {
      throw new ApiError(400, "invalid_week", "weekNumber must be an integer between 1 and 12");
    }

    const body = await parseBody(request, tacticWeekPutSchema);
    const tactic = await loadTactic(ctx.userId, id);

    if (body.done) {
      await db
        .insert(tacticCompletions)
        .values({ tacticId: tactic.id, weekNumber })
        .onConflictDoNothing();
    } else {
      await db
        .delete(tacticCompletions)
        .where(
          and(
            eq(tacticCompletions.tacticId, tactic.id),
            eq(tacticCompletions.weekNumber, weekNumber),
          ),
        );
    }

    const completions = await completedWeeksByTactic([tactic.id]);
    return NextResponse.json({
      tacticId: tactic.id,
      weekNumber,
      done: body.done,
      completedWeeks: completions.get(tactic.id) ?? [],
    });
  },
);

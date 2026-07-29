import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { goals } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { goalValuePutSchema } from "@/lib/validation";
import { withMilestones } from "../../route";

export const runtime = "nodejs";

/**
 * "I'm at 3,400 now." A PUT of an absolute value rather than a delta, so a
 * replayed write from the offline queue lands on the same number.
 */
export const PUT = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const body = await parseBody(request, goalValuePutSchema);

    const goal = await db.query.goals.findFirst({
      where: and(eq(goals.id, id), eq(goals.userId, ctx.userId)),
    });
    if (!goal) throw new ApiError(404, "not_found", "Goal not found");
    if (goal.targetValue === null) {
      throw new ApiError(400, "not_tracked", "This goal has no numeric target");
    }

    const [updated] = await db
      .update(goals)
      .set({ currentValue: body.currentValue, updatedAt: new Date() })
      .where(and(eq(goals.id, id), eq(goals.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Goal not found");

    const [serialized] = await withMilestones(ctx.userId, [updated], todayKey(ctx.settings));
    return NextResponse.json(serialized);
  },
);

import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { goals } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { goalPatchSchema } from "@/lib/validation";
import { withMilestones } from "../route";

export const runtime = "nodejs";

async function loadGoal(userId: string, id: string) {
  const goal = await db.query.goals.findFirst({
    where: and(eq(goals.id, id), eq(goals.userId, userId)),
  });
  if (!goal) throw new ApiError(404, "not_found", "Goal not found");
  return goal;
}

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const goal = await loadGoal(ctx.userId, id);
    const [serialized] = await withMilestones(ctx.userId, [goal], todayKey(ctx.settings));
    return NextResponse.json(serialized);
  },
);

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, goalPatchSchema);
    const today = todayKey(ctx.settings);
    const existing = await loadGoal(ctx.userId, id);

    // The date pair has to stay ordered even when only one side is patched.
    const startDate = patch.startDate ?? existing.startDate;
    const targetDate = patch.targetDate ?? existing.targetDate;
    if (startDate > targetDate) {
      throw new ApiError(400, "validation_error", "targetDate must be on or after startDate");
    }

    const goal =
      Object.keys(patch).length === 0
        ? existing
        : ((
            await db
              .update(goals)
              .set({
                ...patch,
                // Achieving a goal stamps the date it happened; reopening clears it.
                completedAt:
                  patch.status === undefined
                    ? existing.completedAt
                    : patch.status === "achieved"
                      ? (existing.completedAt ?? new Date())
                      : null,
                updatedAt: new Date(),
              })
              .where(and(eq(goals.id, id), eq(goals.userId, ctx.userId)))
              .returning()
          )[0] ?? existing);

    const [serialized] = await withMilestones(ctx.userId, [goal], today);
    return NextResponse.json(serialized);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const [deleted] = await db
      .delete(goals)
      .where(and(eq(goals.id, id), eq(goals.userId, ctx.userId)))
      .returning();
    if (!deleted) throw new ApiError(404, "not_found", "Goal not found");

    return NextResponse.json({ ok: true });
  },
);

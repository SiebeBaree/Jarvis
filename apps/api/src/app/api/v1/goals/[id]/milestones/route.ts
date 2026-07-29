import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { goalMilestones, goals } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { milestoneCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const body = await parseBody(request, milestoneCreateSchema);

    const goal = await db.query.goals.findFirst({
      where: and(eq(goals.id, id), eq(goals.userId, ctx.userId)),
    });
    if (!goal) throw new ApiError(404, "not_found", "Goal not found");

    const [created] = await db
      .insert(goalMilestones)
      .values({
        id: body.id,
        userId: ctx.userId,
        goalId: id,
        title: body.title,
        sortOrder: body.sortOrder ?? 0,
      })
      // Client-chosen id: a replayed create is a no-op, not a duplicate row.
      .onConflictDoNothing()
      .returning();

    if (created) return NextResponse.json(created, { status: 201 });

    const existing = body.id
      ? await db.query.goalMilestones.findFirst({
          where: and(eq(goalMilestones.id, body.id), eq(goalMilestones.userId, ctx.userId)),
        })
      : undefined;
    if (!existing) throw new ApiError(500, "internal_error", "Could not create milestone");
    return NextResponse.json(existing);
  },
);

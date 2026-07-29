import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { goalMilestones } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { milestonePatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, milestonePatchSchema);

    const existing = await db.query.goalMilestones.findFirst({
      where: and(eq(goalMilestones.id, id), eq(goalMilestones.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Milestone not found");

    // `done` is a boolean over the wire but a timestamp in the row; ticking an
    // already-done milestone keeps its original date, so a replay is a no-op.
    const doneAt =
      patch.done === undefined
        ? existing.doneAt
        : patch.done
          ? (existing.doneAt ?? new Date())
          : null;

    const [updated] = await db
      .update(goalMilestones)
      .set({
        title: patch.title ?? existing.title,
        sortOrder: patch.sortOrder ?? existing.sortOrder,
        doneAt,
      })
      .where(and(eq(goalMilestones.id, id), eq(goalMilestones.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Milestone not found");

    return NextResponse.json(updated);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const [deleted] = await db
      .delete(goalMilestones)
      .where(and(eq(goalMilestones.id, id), eq(goalMilestones.userId, ctx.userId)))
      .returning();
    if (!deleted) throw new ApiError(404, "not_found", "Milestone not found");

    return NextResponse.json({ ok: true });
  },
);

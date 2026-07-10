import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { tasks } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { recomputeDay } from "@/lib/scoring/snapshot";
import { withSubtasks } from "@/lib/today";
import { taskPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, taskPatchSchema);

    const existing = await db.query.tasks.findFirst({
      where: and(eq(tasks.id, id), eq(tasks.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Task not found");

    const [updated] = await db
      .update(tasks)
      .set({ ...patch, updatedAt: new Date() })
      .where(and(eq(tasks.id, id), eq(tasks.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Task not found");

    const daysToRecompute = new Set<string>();
    if (existing.dueDate !== updated.dueDate) {
      if (existing.dueDate) daysToRecompute.add(existing.dueDate);
      if (updated.dueDate) daysToRecompute.add(updated.dueDate);
    }
    if (patch.status !== undefined && patch.status !== existing.status && updated.dueDate) {
      daysToRecompute.add(updated.dueDate);
    }
    for (const day of daysToRecompute) {
      await recomputeDay(ctx.userId, ctx.settings, day);
    }

    const [dto] = await withSubtasks([updated]);
    return NextResponse.json(dto);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const existing = await db.query.tasks.findFirst({
      where: and(eq(tasks.id, id), eq(tasks.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Task not found");

    await db.delete(tasks).where(and(eq(tasks.id, id), eq(tasks.userId, ctx.userId)));

    if (existing.dueDate) {
      await recomputeDay(ctx.userId, ctx.settings, existing.dueDate);
    }

    return NextResponse.json({ ok: true });
  },
);

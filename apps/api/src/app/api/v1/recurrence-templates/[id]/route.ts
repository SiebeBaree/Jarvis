import { NextResponse } from "next/server";
import { and, eq, gt, lte, ne, or } from "drizzle-orm";
import { db } from "@/db/client";
import { recurrenceTemplates, tasks } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { materializeTemplates } from "@/lib/today";
import { templatePatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, templatePatchSchema);

    const existing = await db.query.recurrenceTemplates.findFirst({
      where: and(eq(recurrenceTemplates.id, id), eq(recurrenceTemplates.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Template not found");

    const today = todayKey(ctx.settings);

    const set: Partial<typeof recurrenceTemplates.$inferInsert> = {};
    if (patch.title !== undefined) set.title = patch.title;
    if (patch.notes !== undefined) set.notes = patch.notes;
    if (patch.priority !== undefined) set.priority = patch.priority;
    if (patch.categoryId !== undefined) set.categoryId = patch.categoryId;
    if (patch.dueTime !== undefined) set.dueTime = patch.dueTime;
    if (patch.rule !== undefined) set.rule = patch.rule;
    if (patch.startDate !== undefined) set.startDate = patch.startDate;
    if (patch.endDate !== undefined) set.endDate = patch.endDate;
    if (patch.paused === true) set.pausedAt = existing.pausedAt ?? new Date();
    if (patch.paused === false) set.pausedAt = null;

    // Content edits affect FUTURE occurrences only: drop open, not-yet-due
    // occurrences and regenerate them from the updated template.
    const contentChanged =
      patch.title !== undefined ||
      patch.notes !== undefined ||
      patch.priority !== undefined ||
      patch.categoryId !== undefined ||
      patch.dueTime !== undefined ||
      patch.rule !== undefined ||
      patch.startDate !== undefined ||
      patch.endDate !== undefined;

    if (contentChanged) {
      await db
        .delete(tasks)
        .where(
          and(
            eq(tasks.userId, ctx.userId),
            eq(tasks.templateId, id),
            gt(tasks.templateDate, today),
            eq(tasks.status, "open"),
          ),
        );
      set.lastGeneratedThrough = today;
    }

    if (Object.keys(set).length > 0) {
      await db
        .update(recurrenceTemplates)
        .set(set)
        .where(and(eq(recurrenceTemplates.id, id), eq(recurrenceTemplates.userId, ctx.userId)));
    }

    if (contentChanged) {
      await materializeTemplates(ctx.userId, ctx.settings);
    }

    const updated = await db.query.recurrenceTemplates.findFirst({
      where: eq(recurrenceTemplates.id, id),
    });
    if (!updated) throw new ApiError(404, "not_found", "Template not found");
    return NextResponse.json(updated);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const existing = await db.query.recurrenceTemplates.findFirst({
      where: and(eq(recurrenceTemplates.id, id), eq(recurrenceTemplates.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Template not found");

    const today = todayKey(ctx.settings);

    // Preserve history: detach past/handled occurrences before the template's
    // cascade deletes the remaining open future ones.
    await db
      .update(tasks)
      .set({ templateId: null })
      .where(
        and(
          eq(tasks.userId, ctx.userId),
          eq(tasks.templateId, id),
          or(ne(tasks.status, "open"), lte(tasks.templateDate, today)),
        ),
      );

    await db
      .delete(recurrenceTemplates)
      .where(and(eq(recurrenceTemplates.id, id), eq(recurrenceTemplates.userId, ctx.userId)));

    return NextResponse.json({ ok: true });
  },
);

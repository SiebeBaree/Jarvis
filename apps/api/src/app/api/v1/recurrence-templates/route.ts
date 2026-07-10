import { NextResponse } from "next/server";
import { desc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { recurrenceTemplates } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { materializeTemplates } from "@/lib/today";
import { templateCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const templates = await db.query.recurrenceTemplates.findMany({
    where: eq(recurrenceTemplates.userId, ctx.userId),
    orderBy: [desc(recurrenceTemplates.createdAt)],
  });
  return NextResponse.json({ templates });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, templateCreateSchema);

  const [created] = await db
    .insert(recurrenceTemplates)
    .values({
      userId: ctx.userId,
      title: body.title,
      notes: body.notes ?? null,
      priority: body.priority ?? "medium",
      goalId: body.goalId ?? null,
      dueTime: body.dueTime ?? null,
      rule: body.rule,
      startDate: body.startDate,
      endDate: body.endDate ?? null,
      showInReviewWeek: body.showInReviewWeek ?? false,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create template");

  await materializeTemplates(ctx.userId, ctx.settings);

  // Re-read: materialization advanced lastGeneratedThrough.
  const fresh = await db.query.recurrenceTemplates.findFirst({
    where: eq(recurrenceTemplates.id, created.id),
  });
  return NextResponse.json(fresh ?? created, { status: 201 });
});

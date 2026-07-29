import { NextResponse } from "next/server";
import { and, asc, desc, eq, gt, gte, isNull, lte, ne, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { tasks } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, parseQuery } from "@/lib/http";
import { recomputeDay, todayKey } from "@/lib/scoring/snapshot";
import { materializeTemplates, withSubtasks } from "@/lib/today";
import { taskCreateSchema, taskListQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 30; // cold start + Neon wake must not be cut short

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, taskListQuerySchema);
  const today = todayKey(ctx.settings);
  const view = query.view ?? "all";

  // Ensure recurring occurrences exist before listing near-term work.
  if (view === "today" || view === "upcoming") {
    await materializeTemplates(ctx.userId, ctx.settings);
  }

  const conditions: SQL[] = [eq(tasks.userId, ctx.userId), isNull(tasks.parentTaskId)];
  let orderBy: SQL[] = [asc(tasks.dueDate), asc(tasks.sortOrder), asc(tasks.createdAt)];
  let limit = 500;

  switch (view) {
    case "today":
      conditions.push(eq(tasks.dueDate, today));
      break;
    case "upcoming":
      conditions.push(gt(tasks.dueDate, today), eq(tasks.status, "open"));
      break;
    case "inbox":
      conditions.push(isNull(tasks.dueDate), eq(tasks.status, "open"));
      break;
    case "done":
      conditions.push(eq(tasks.status, "done"));
      orderBy = [desc(tasks.completedAt)];
      limit = 100;
      break;
    case "all":
      conditions.push(ne(tasks.status, "cancelled"));
      break;
  }

  if (query.dueFrom) conditions.push(gte(tasks.dueDate, query.dueFrom));
  if (query.dueTo) conditions.push(lte(tasks.dueDate, query.dueTo));
  if (query.categoryId) conditions.push(eq(tasks.categoryId, query.categoryId));
  if (query.status) conditions.push(eq(tasks.status, query.status));

  const rows = await db.query.tasks.findMany({ where: and(...conditions), orderBy, limit });
  return NextResponse.json({ tasks: await withSubtasks(rows) });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, taskCreateSchema);

  if (body.parentTaskId) {
    const parent = await db.query.tasks.findFirst({
      where: and(eq(tasks.id, body.parentTaskId), eq(tasks.userId, ctx.userId)),
    });
    if (!parent) throw new ApiError(404, "not_found", "Parent task not found");
    if (parent.parentTaskId) {
      throw new ApiError(400, "nesting_too_deep", "Subtasks cannot have their own subtasks");
    }
  }

  const insert = db.insert(tasks).values({
    id: body.id,
    userId: ctx.userId,
    title: body.title,
    notes: body.notes ?? null,
    dueDate: body.dueDate ?? null,
    dueTime: body.dueTime ?? null,
    priority: body.priority ?? "medium",
    categoryId: body.categoryId ?? null,
    parentTaskId: body.parentTaskId ?? null,
    sortOrder: body.sortOrder ?? 0,
  });
  // A client-chosen id makes a retried create a no-op instead of a duplicate.
  const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();

  if (!created) {
    if (!body.id) throw new ApiError(500, "internal_error", "Could not create task");
    const existing = await db.query.tasks.findFirst({ where: eq(tasks.id, body.id) });
    if (!existing) throw new ApiError(500, "internal_error", "Could not create task");
    if (existing.userId !== ctx.userId) {
      throw new ApiError(409, "id_conflict", "That task id is already taken");
    }
    return NextResponse.json({ ...existing, subtasks: [] });
  }

  if (created.dueDate) {
    await recomputeDay(ctx.userId, ctx.settings, created.dueDate);
  }

  return NextResponse.json({ ...created, subtasks: [] }, { status: 201 });
});

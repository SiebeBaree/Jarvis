import { NextResponse } from "next/server";
import { and, asc, eq, isNull, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { taskCategories } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { taskCategoryCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const includeArchived =
    new URL(request.url).searchParams.get("includeArchived") === "true";

  const conditions: SQL[] = [eq(taskCategories.userId, ctx.userId)];
  if (!includeArchived) conditions.push(isNull(taskCategories.archivedAt));

  const rows = await db.query.taskCategories.findMany({
    where: and(...conditions),
    orderBy: [asc(taskCategories.sortOrder), asc(taskCategories.name)],
  });
  return NextResponse.json({ categories: rows });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, taskCategoryCreateSchema);

  const duplicate = await db.query.taskCategories.findFirst({
    where: and(eq(taskCategories.userId, ctx.userId), eq(taskCategories.name, body.name)),
  });
  if (duplicate) {
    throw new ApiError(409, "name_exists", "A category with that name already exists");
  }

  const [created] = await db
    .insert(taskCategories)
    .values({
      userId: ctx.userId,
      name: body.name,
      emoji: body.emoji ?? null,
      colorHex: body.colorHex ?? null,
      sortOrder: body.sortOrder ?? 0,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create category");

  return NextResponse.json(created, { status: 201 });
});

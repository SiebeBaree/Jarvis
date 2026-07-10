import { NextResponse } from "next/server";
import { and, asc, eq, ne, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks, goals } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, parseQuery } from "@/lib/http";
import { goalCreateSchema, goalListQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, goalListQuerySchema);

  const conditions: SQL[] = [eq(goals.userId, ctx.userId)];
  if (query.includeDropped !== "true") conditions.push(ne(goals.status, "dropped"));
  if (query.blockId) conditions.push(eq(goals.blockId, query.blockId));

  const rows = await db.query.goals.findMany({
    where: and(...conditions),
    orderBy: [asc(goals.sortOrder), asc(goals.createdAt)],
  });
  return NextResponse.json({ goals: rows });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, goalCreateSchema);

  if (body.blockId) {
    const block = await db.query.blocks.findFirst({
      where: and(eq(blocks.id, body.blockId), eq(blocks.userId, ctx.userId)),
    });
    if (!block) throw new ApiError(404, "not_found", "Block not found");
  }

  const [created] = await db
    .insert(goals)
    .values({
      userId: ctx.userId,
      title: body.title,
      description: body.description ?? null,
      areaId: body.areaId ?? null,
      blockId: body.blockId ?? null,
      trackStatus: body.trackStatus ?? null,
      manualProgress: body.manualProgress ?? null,
      sortOrder: body.sortOrder ?? 0,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create goal");

  return NextResponse.json(created, { status: 201 });
});

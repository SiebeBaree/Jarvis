import { NextResponse } from "next/server";
import { and, asc, eq, isNull, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import { areas } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { areaCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const includeArchived =
    new URL(request.url).searchParams.get("includeArchived") === "true";

  const conditions: SQL[] = [eq(areas.userId, ctx.userId)];
  if (!includeArchived) conditions.push(isNull(areas.archivedAt));

  const rows = await db.query.areas.findMany({
    where: and(...conditions),
    orderBy: [asc(areas.sortOrder), asc(areas.name)],
  });
  return NextResponse.json({ areas: rows });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, areaCreateSchema);

  const duplicate = await db.query.areas.findFirst({
    where: and(eq(areas.userId, ctx.userId), eq(areas.name, body.name)),
  });
  if (duplicate) throw new ApiError(409, "name_exists", "An area with that name already exists");

  const [created] = await db
    .insert(areas)
    .values({
      userId: ctx.userId,
      name: body.name,
      emoji: body.emoji ?? null,
      colorHex: body.colorHex ?? null,
      sortOrder: body.sortOrder ?? 0,
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create area");

  return NextResponse.json(created, { status: 201 });
});

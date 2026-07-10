import { NextResponse } from "next/server";
import { desc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { blocks } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { BLOCK_LENGTH_DAYS, prepareBlockSlot, snapToMonday } from "@/lib/blocks";
import { addDays } from "@/lib/daykey";
import { ApiError, handler, parseBody } from "@/lib/http";
import { blockCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const rows = await db.query.blocks.findMany({
    where: eq(blocks.userId, ctx.userId),
    orderBy: [desc(blocks.startDate)],
  });
  return NextResponse.json({ blocks: rows });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, blockCreateSchema);

  const startDate = snapToMonday(body.startDate);
  const endDate = addDays(startDate, BLOCK_LENGTH_DAYS);
  const { hasActive, nextNumber } = await prepareBlockSlot(ctx.userId, startDate, endDate);

  const [created] = await db
    .insert(blocks)
    .values({
      userId: ctx.userId,
      number: nextNumber,
      title: body.title,
      startDate,
      endDate,
      status: hasActive ? "planned" : "active",
    })
    .returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create block");

  return NextResponse.json(created, { status: 201 });
});

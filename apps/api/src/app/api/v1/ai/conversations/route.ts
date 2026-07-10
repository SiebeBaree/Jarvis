import { NextResponse } from "next/server";
import { desc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { conversations } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";

export const runtime = "nodejs";

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);

  const rows = await db.query.conversations.findMany({
    where: eq(conversations.userId, ctx.userId),
    orderBy: [desc(conversations.updatedAt)],
    limit: 50,
  });

  return NextResponse.json({
    conversations: rows.map((c) => ({
      id: c.id,
      kind: c.kind,
      title: c.title,
      blockId: c.blockId,
      weekNumber: c.weekNumber,
      hasOutcome: c.outcome != null,
      updatedAt: c.updatedAt,
      createdAt: c.createdAt,
    })),
  });
});

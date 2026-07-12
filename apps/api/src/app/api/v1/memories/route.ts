// The user-visible side of the AI's long-term memory: list everything it
// knows, add facts manually. Edits/deletes live in [id]/route.ts.

import { NextResponse } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { memories } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody, ApiError } from "@/lib/http";
import { memoryCreateSchema } from "@/lib/validation";

export const runtime = "nodejs";

// Route files may only export handlers — keep helpers module-local.
function memoryDTO(row: typeof memories.$inferSelect) {
  return {
    id: row.id,
    category: row.category,
    content: row.content,
    source: row.source,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const rows = await db.query.memories.findMany({
    where: eq(memories.userId, ctx.userId),
    orderBy: [asc(memories.category), asc(memories.createdAt)],
  });
  return NextResponse.json({ memories: rows.map(memoryDTO) });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, memoryCreateSchema);
  const [row] = await db
    .insert(memories)
    .values({ userId: ctx.userId, category: body.category, content: body.content, source: "manual" })
    .returning();
  if (!row) throw new ApiError(500, "internal_error", "Could not save memory");
  return NextResponse.json(memoryDTO(row), { status: 201 });
});

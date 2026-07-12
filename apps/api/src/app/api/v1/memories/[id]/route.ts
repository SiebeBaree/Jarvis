import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { memories } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { memoryPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

type Params = { params: Promise<{ id: string }> };

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

async function loadMemory(userId: string, id: string) {
  const row = await db.query.memories.findFirst({
    where: and(eq(memories.id, id), eq(memories.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Memory not found");
  return row;
}

export const PATCH = handler(async (request: Request, { params }: Params) => {
  const ctx = await requireAuth(request);
  const { id } = await params;
  const body = await parseBody(request, memoryPatchSchema);
  await loadMemory(ctx.userId, id);
  const [updated] = await db
    .update(memories)
    .set({
      ...(body.category ? { category: body.category } : {}),
      ...(body.content ? { content: body.content } : {}),
      updatedAt: new Date(),
    })
    .where(eq(memories.id, id))
    .returning();
  return NextResponse.json(memoryDTO(updated!));
});

export const DELETE = handler(async (request: Request, { params }: Params) => {
  const ctx = await requireAuth(request);
  const { id } = await params;
  await loadMemory(ctx.userId, id);
  await db.delete(memories).where(eq(memories.id, id));
  return NextResponse.json({ ok: true });
});

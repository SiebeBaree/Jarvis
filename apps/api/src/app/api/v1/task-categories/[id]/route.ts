import { NextResponse } from "next/server";
import { and, eq, ne } from "drizzle-orm";
import { db } from "@/db/client";
import { taskCategories } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { taskCategoryPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, taskCategoryPatchSchema);

    const existing = await db.query.taskCategories.findFirst({
      where: and(eq(taskCategories.id, id), eq(taskCategories.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Category not found");

    if (patch.name !== undefined) {
      const duplicate = await db.query.taskCategories.findFirst({
        where: and(
          eq(taskCategories.userId, ctx.userId),
          eq(taskCategories.name, patch.name),
          ne(taskCategories.id, id),
        ),
      });
      if (duplicate) {
        throw new ApiError(409, "name_exists", "A category with that name already exists");
      }
    }

    const { archived, ...fields } = patch;
    const set: Partial<typeof taskCategories.$inferInsert> = { ...fields };
    if (archived === true) set.archivedAt = existing.archivedAt ?? new Date();
    if (archived === false) set.archivedAt = null;
    if (Object.keys(set).length === 0) return NextResponse.json(existing);

    const [updated] = await db
      .update(taskCategories)
      .set(set)
      .where(and(eq(taskCategories.id, id), eq(taskCategories.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Category not found");

    return NextResponse.json(updated);
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    // Tasks in the category survive — their categoryId nulls via FK.
    const [deleted] = await db
      .delete(taskCategories)
      .where(and(eq(taskCategories.id, id), eq(taskCategories.userId, ctx.userId)))
      .returning();
    if (!deleted) throw new ApiError(404, "not_found", "Category not found");

    return NextResponse.json({ ok: true });
  },
);

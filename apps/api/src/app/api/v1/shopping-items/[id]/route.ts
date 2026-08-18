import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { shoppingItems } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { shoppingItemPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

function itemDTO(row: typeof shoppingItems.$inferSelect) {
  return {
    id: row.id,
    name: row.name,
    quantity: row.quantity,
    checked: row.checkedAt !== null,
    checkedAt: row.checkedAt,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
  };
}

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, shoppingItemPatchSchema);

    const existing = await db.query.shoppingItems.findFirst({
      where: and(eq(shoppingItems.id, id), eq(shoppingItems.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Item not found");

    const set: Partial<typeof shoppingItems.$inferInsert> = {};
    if (patch.name !== undefined) set.name = patch.name.trim();
    if (patch.quantity !== undefined) set.quantity = patch.quantity;
    if (patch.sortOrder !== undefined) set.sortOrder = patch.sortOrder;
    // Absolute rather than a toggle, so a replayed check never un-checks.
    if (patch.checked === true) set.checkedAt = existing.checkedAt ?? new Date();
    if (patch.checked === false) set.checkedAt = null;

    if (Object.keys(set).length === 0) {
      return NextResponse.json(itemDTO(existing));
    }

    const [updated] = await db
      .update(shoppingItems)
      .set(set)
      .where(and(eq(shoppingItems.id, id), eq(shoppingItems.userId, ctx.userId)))
      .returning();
    if (!updated) throw new ApiError(404, "not_found", "Item not found");
    return NextResponse.json(itemDTO(updated));
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const existing = await db.query.shoppingItems.findFirst({
      where: and(eq(shoppingItems.id, id), eq(shoppingItems.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Item not found");

    await db
      .delete(shoppingItems)
      .where(and(eq(shoppingItems.id, id), eq(shoppingItems.userId, ctx.userId)));
    return NextResponse.json({ ok: true });
  },
);

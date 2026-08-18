// One standing shopping list. Unchecked items first in the user's own order,
// then what has already gone in the trolley — which is the order you want
// while walking round a shop, and it means "clear" is the only tidying action
// the list ever needs.

import { NextResponse } from "next/server";
import { asc, eq, sql } from "drizzle-orm";
import { db } from "@/db/client";
import { shoppingItems } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody, resolveIdempotentCreate } from "@/lib/http";
import { shoppingItemCreateSchema } from "@/lib/validation";

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

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const rows = await db
    .select()
    .from(shoppingItems)
    .where(eq(shoppingItems.userId, ctx.userId))
    .orderBy(asc(shoppingItems.sortOrder), asc(shoppingItems.createdAt))
    .limit(500);
  return NextResponse.json({ items: rows.map(itemDTO) });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, shoppingItemCreateSchema);

  let sortOrder = body.sortOrder;
  if (sortOrder === undefined) {
    // New items land at the bottom of the list, not the top: you add in the
    // order things occur to you, and that is the order you want to read back.
    const [row] = await db
      .select({ next: sql<number>`coalesce(max(${shoppingItems.sortOrder}), 0) + 1` })
      .from(shoppingItems)
      .where(eq(shoppingItems.userId, ctx.userId));
    sortOrder = row?.next ?? 0;
  }

  const insert = db.insert(shoppingItems).values({
    id: body.id,
    userId: ctx.userId,
    name: body.name.trim(),
    quantity: body.quantity ?? null,
    sortOrder,
  });

  const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();
  if (created) return NextResponse.json(itemDTO(created), { status: 201 });

  const existing = await resolveIdempotentCreate(ctx.userId, "shopping item", () =>
    db.query.shoppingItems.findFirst({ where: eq(shoppingItems.id, body.id!) }),
  );
  return NextResponse.json(itemDTO(existing));
});

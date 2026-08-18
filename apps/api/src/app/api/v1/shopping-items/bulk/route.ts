// Bulk add — how a meal prep's ingredients get onto the list in one tap.
//
// Names already on the list (and not yet checked off) are skipped rather than
// duplicated: adding two recipes that both want olive oil should leave one
// line, because that is what you will buy.

import { NextResponse } from "next/server";
import { asc, eq, sql } from "drizzle-orm";
import { db } from "@/db/client";
import { shoppingItems } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody } from "@/lib/http";
import { shoppingBulkAddSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, shoppingBulkAddSchema);

  const existing = await db
    .select({ name: shoppingItems.name, checkedAt: shoppingItems.checkedAt })
    .from(shoppingItems)
    .where(eq(shoppingItems.userId, ctx.userId));
  const openNames = new Set(
    existing.filter((row) => row.checkedAt === null).map((row) => row.name.toLowerCase()),
  );

  const [maxRow] = await db
    .select({ next: sql<number>`coalesce(max(${shoppingItems.sortOrder}), 0) + 1` })
    .from(shoppingItems)
    .where(eq(shoppingItems.userId, ctx.userId));
  let sortOrder = maxRow?.next ?? 0;

  const seen = new Set<string>();
  const values = [];
  for (const item of body.items) {
    const name = item.name.trim();
    const key = name.toLowerCase();
    if (!name || openNames.has(key) || seen.has(key)) continue;
    seen.add(key);
    values.push({
      id: item.id,
      userId: ctx.userId,
      name,
      quantity: item.quantity ?? null,
      sortOrder: sortOrder++,
    });
  }

  if (values.length > 0) {
    await db.insert(shoppingItems).values(values).onConflictDoNothing();
  }

  const rows = await db
    .select()
    .from(shoppingItems)
    .where(eq(shoppingItems.userId, ctx.userId))
    .orderBy(asc(shoppingItems.sortOrder), asc(shoppingItems.createdAt))
    .limit(500);

  return NextResponse.json({
    added: values.length,
    skipped: body.items.length - values.length,
    items: rows.map((row) => ({
      id: row.id,
      name: row.name,
      quantity: row.quantity,
      checked: row.checkedAt !== null,
      checkedAt: row.checkedAt,
      sortOrder: row.sortOrder,
      createdAt: row.createdAt,
    })),
  });
});

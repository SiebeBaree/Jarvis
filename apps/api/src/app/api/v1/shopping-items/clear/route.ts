// Clearing the list. A POST rather than a DELETE with a query string, because
// this goes through the app's offline outbox, which stores a mutation as
// (method, path, JSON body) and percent-encodes the path — a `?scope=` would
// not survive the trip. Clearing twice is harmless, so replay safety is free.

import { NextResponse } from "next/server";
import { and, eq, isNotNull } from "drizzle-orm";
import { db } from "@/db/client";
import { shoppingItems } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody } from "@/lib/http";
import { shoppingClearSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, shoppingClearSchema);

  await db
    .delete(shoppingItems)
    .where(
      body.scope === "all"
        ? eq(shoppingItems.userId, ctx.userId)
        : and(eq(shoppingItems.userId, ctx.userId), isNotNull(shoppingItems.checkedAt)),
    );
  return NextResponse.json({ ok: true });
});

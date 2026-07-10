import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { tactics } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { completedWeeksByTactic, loadTactic } from "@/lib/tactics";
import { tacticPatchSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const PATCH = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const patch = await parseBody(request, tacticPatchSchema);
    const existing = await loadTactic(ctx.userId, id);

    const fromWeek = patch.fromWeek ?? existing.fromWeek;
    const toWeek = patch.toWeek ?? existing.toWeek;
    if (fromWeek > toWeek) {
      throw new ApiError(400, "invalid_week_range", "fromWeek must be <= toWeek");
    }

    const row =
      Object.keys(patch).length === 0
        ? existing
        : (await db.update(tactics).set(patch).where(eq(tactics.id, existing.id)).returning())[0];
    if (!row) throw new ApiError(404, "not_found", "Tactic not found");

    const completions = await completedWeeksByTactic([row.id]);
    return NextResponse.json({ ...row, completedWeeks: completions.get(row.id) ?? [] });
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const tactic = await loadTactic(ctx.userId, id);

    await db.delete(tactics).where(eq(tactics.id, tactic.id));
    return NextResponse.json({ ok: true });
  },
);

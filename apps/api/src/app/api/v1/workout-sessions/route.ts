// Workout sessions: the history list, and starting a new one.

import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { workoutSessions } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody, parseQuery, resolveIdempotentCreate } from "@/lib/http";
import { todayKey } from "@/lib/scoring/snapshot";
import { buildSessionDetail, listSessionSummaries, loadRoutine } from "@/lib/training";
import { sessionCreateSchema, sessionListQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 30;

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const query = parseQuery(request, sessionListQuerySchema);
  const sessions = await listSessionSummaries(ctx.userId, query);
  return NextResponse.json({ sessions });
});

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, sessionCreateSchema);

  let title = body.title?.trim();
  if (body.routineId) {
    const routine = await loadRoutine(ctx.userId, body.routineId);
    title ??= routine.name;
  }
  if (!title) {
    throw new ApiError(400, "missing_title", "A workout needs a routine or a title");
  }

  const insert = db.insert(workoutSessions).values({
    id: body.id,
    userId: ctx.userId,
    routineId: body.routineId ?? null,
    title,
    dayKey: body.dayKey ?? todayKey(ctx.settings),
  });

  // A client-chosen id makes "start workout" replay-safe: tapping start with
  // no signal queues the create, and a retry resumes the same session instead
  // of opening a second one.
  const [created] = await (body.id ? insert.onConflictDoNothing() : insert).returning();
  const session =
    created ??
    (await resolveIdempotentCreate(ctx.userId, "workout", () =>
      db.query.workoutSessions.findFirst({ where: eq(workoutSessions.id, body.id!) }),
    ));

  const detail = await buildSessionDetail(ctx.userId, session);
  return NextResponse.json(detail, { status: created ? 201 : 200 });
});

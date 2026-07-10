// "Resume draft" on app launch: the most recent session still worth showing —
// active (mid-interview) or completed (result awaiting review/apply).

import { NextResponse } from "next/server";
import { and, desc, eq, inArray } from "drizzle-orm";
import { db } from "@/db/client";
import { interviewSessions } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";

export const runtime = "nodejs";

type TranscriptEntry = {
  round?: number;
  phase?: string;
  phaseIndex?: number;
  questions?: unknown[];
};

export const GET = handler(async (request: Request) => {
  const ctx = await requireAuth(request);

  const session = await db.query.interviewSessions.findFirst({
    where: and(
      eq(interviewSessions.userId, ctx.userId),
      inArray(interviewSessions.status, ["active", "completed"]),
    ),
    orderBy: [desc(interviewSessions.createdAt)],
  });
  if (!session) throw new ApiError(404, "not_found", "No interview in progress");

  // Active session: reconstruct the pending round from the last transcript entry.
  let round: Record<string, unknown> | null = null;
  if (session.status === "active") {
    const last = session.transcript[session.transcript.length - 1] as TranscriptEntry | undefined;
    if (last) {
      round = {
        done: false,
        phase: last.phase ?? "",
        phaseIndex: last.phaseIndex ?? 0,
        questions: last.questions ?? [],
        result: null,
      };
    }
  }

  return NextResponse.json({
    sessionId: session.id,
    kind: session.kind,
    status: session.status,
    round,
    result: session.status === "completed" ? (session.result ?? null) : null,
  });
});

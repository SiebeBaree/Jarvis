import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { interviewSessions } from "@/db/schema";
import { answerInterviewRound, answersSchema } from "@/lib/ai/interview";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";

export const runtime = "nodejs";
export const maxDuration = 180; // deep model calls are slow

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const body = await parseBody(request, answersSchema);

    const session = await db.query.interviewSessions.findFirst({
      where: and(eq(interviewSessions.id, id), eq(interviewSessions.userId, ctx.userId)),
    });
    if (!session) throw new ApiError(404, "not_found", "Interview session not found");

    const { round } = await answerInterviewRound(session, body.answers, ctx.settings.aiOverrides);
    return NextResponse.json({ round });
  },
);

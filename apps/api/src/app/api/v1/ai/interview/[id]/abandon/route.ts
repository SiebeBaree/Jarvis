import { NextResponse } from "next/server";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { interviewSessions } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const session = await db.query.interviewSessions.findFirst({
      where: and(eq(interviewSessions.id, id), eq(interviewSessions.userId, ctx.userId)),
    });
    if (!session) throw new ApiError(404, "not_found", "Interview session not found");
    if (session.status === "applied") {
      throw new ApiError(409, "already_applied", "This interview was already applied");
    }
    if (session.status === "abandoned") {
      throw new ApiError(409, "already_abandoned", "This interview was already abandoned");
    }

    await db
      .update(interviewSessions)
      .set({ status: "abandoned" })
      .where(eq(interviewSessions.id, session.id));

    return NextResponse.json({ ok: true });
  },
);

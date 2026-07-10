import { NextResponse } from "next/server";
import { rejectProposedAction } from "@/lib/ai/agent";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const action = await rejectProposedAction(ctx.userId, id);
    return NextResponse.json({ action });
  },
);

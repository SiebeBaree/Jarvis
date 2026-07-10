// Confirming executes the STORED args deterministically (no model call);
// executors recompute affected snapshots themselves.

import { NextResponse } from "next/server";
import { confirmProposedAction } from "@/lib/ai/agent";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;

    const action = await confirmProposedAction({ userId: ctx.userId, settings: ctx.settings }, id);
    return NextResponse.json({ action });
  },
);

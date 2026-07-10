import { NextResponse } from "next/server";
import { applyPayloadSchema, applyPlan } from "@/lib/ai/apply-plan";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody } from "@/lib/http";

export const runtime = "nodejs";
export const maxDuration = 60;

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const payload = await parseBody(request, applyPayloadSchema);

    const result = await applyPlan(ctx.userId, ctx.settings, id, payload);
    return NextResponse.json(result);
  },
);

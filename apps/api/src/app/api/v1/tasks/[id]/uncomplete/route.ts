import { NextResponse } from "next/server";
import { requireAuth } from "@/lib/auth";
import { handler } from "@/lib/http";
import { setTaskCompletion } from "@/lib/task-status";

export const runtime = "nodejs";

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const task = await setTaskCompletion(ctx, id, false);
    return NextResponse.json(task);
  },
);

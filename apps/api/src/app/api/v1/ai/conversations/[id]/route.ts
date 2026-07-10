import { NextResponse } from "next/server";
import { and, asc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { conversations, messages } from "@/db/schema";
import { pendingActions } from "@/lib/ai/agent";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";

export const runtime = "nodejs";

async function loadConversation(userId: string, id: string) {
  const conversation = await db.query.conversations.findFirst({
    where: and(eq(conversations.id, id), eq(conversations.userId, userId)),
  });
  if (!conversation) throw new ApiError(404, "not_found", "Conversation not found");
  return conversation;
}

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const conversation = await loadConversation(ctx.userId, id);

    const history = await db.query.messages.findMany({
      where: eq(messages.conversationId, id),
      orderBy: [asc(messages.createdAt)],
    });

    return NextResponse.json({
      conversation: {
        id: conversation.id,
        kind: conversation.kind,
        title: conversation.title,
        blockId: conversation.blockId,
        weekNumber: conversation.weekNumber,
        outcome: conversation.outcome,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
      },
      messages: history.map((m) => ({
        id: m.id,
        role: m.role,
        parts: m.parts,
        createdAt: m.createdAt,
      })),
      actions: await pendingActions(id),
    });
  },
);

export const DELETE = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    await loadConversation(ctx.userId, id);

    // Messages, proposed actions, etc. cascade via FK.
    await db.delete(conversations).where(eq(conversations.id, id));
    return NextResponse.json({ ok: true });
  },
);

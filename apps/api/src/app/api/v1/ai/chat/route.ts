// The chat endpoint: one user turn in, an SSE stream out. Events:
//   meta          → {"conversationId": "..."} (always first)
//   message_delta → {"text": "..."}
//   tool_call     → {"name": "...", "status": "running" | "done"}
//   action        → full proposed_actions row (confirmation card)
//   message_done  → {"messageId": "...", "conversationId": "..."}
//   error         → {"code": "...", "message": "..."} (stream then closes)

import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { conversations } from "@/db/schema";
import { runAgentTurn } from "@/lib/ai/agent";
import type { AITask } from "@/lib/ai/tiers";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { chatRequestSchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 180; // agent turns can chain several model calls

const KIND_TASKS: Record<string, AITask> = {
  chat: "chat",
  weekly_review: "weekly_review",
  block_review: "block_review",
};

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseBody(request, chatRequestSchema);

  let conversation: typeof conversations.$inferSelect;
  if (body.conversationId) {
    const existing = await db.query.conversations.findFirst({
      where: and(eq(conversations.id, body.conversationId), eq(conversations.userId, ctx.userId)),
    });
    if (!existing) throw new ApiError(404, "not_found", "Conversation not found");
    conversation = existing;
  } else {
    const [created] = await db
      .insert(conversations)
      .values({ userId: ctx.userId, kind: "chat" })
      .returning();
    if (!created) throw new ApiError(500, "internal_error", "Could not create conversation");
    conversation = created;
  }

  const task: AITask = KIND_TASKS[conversation.kind] ?? "chat";

  // Review conversations get a seed prompt (built concurrently in @/lib/reviews).
  let extraInstructions: string | undefined;
  if (conversation.kind !== "chat") {
    try {
      const { buildReviewSeed } = await import("@/lib/reviews");
      extraInstructions = (await buildReviewSeed(conversation, ctx.settings)) || undefined;
    } catch {
      // Seeding is additive — a failed build must not block the conversation.
    }
  }

  const { userId, settings } = ctx;
  const { message } = body;
  const conversationId = conversation.id;
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      // A client disconnect makes enqueue throw — swallow it so the turn keeps
      // running to completion server-side (the agent persists in a finally).
      let closed = false;
      const send = (event: string, data: unknown) => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
        } catch {
          closed = true;
        }
      };
      try {
        send("meta", { conversationId });
        const { assistantMessageId } = await runAgentTurn(
          { userId, settings, conversationId, userText: message, task, extraInstructions },
          {
            onDelta: (text) => send("message_delta", { text }),
            onToolStatus: (name, status) => send("tool_call", { name, status }),
            onAction: (action) => send("action", action),
          },
        );
        send("message_done", { messageId: assistantMessageId, conversationId });
      } catch (error) {
        try {
          if (error instanceof ApiError) {
            send("error", { code: error.code, message: error.message });
          } else {
            console.error("Unhandled chat stream error:", error);
            send("error", { code: "internal_error", message: "Something went wrong" });
          }
        } catch {
          // The stream is already gone — nothing left to report to.
        }
      } finally {
        try {
          controller.close();
        } catch {
          // Already closed by the client disconnect.
        }
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
});

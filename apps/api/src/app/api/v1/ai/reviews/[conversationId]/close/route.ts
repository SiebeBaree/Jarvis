// Closes a review conversation: a deep-tier model pass over the transcript
// produces the structured outcome {wins, struggles, adjustments,
// focusNextWeek} stored on conversations.outcome (shown on Week Detail).

import { NextResponse } from "next/server";
import { asc, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/db/client";
import { conversations, messages, type MessagePart } from "@/db/schema";
import { callModel } from "@/lib/ai/provider";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";

export const runtime = "nodejs";
export const maxDuration = 120;

const outcomeSchema = z.strictObject({
  wins: z.array(z.string()),
  struggles: z.array(z.string()),
  adjustments: z.array(z.string()),
  focusNextWeek: z.string(),
});
export type ReviewOutcome = z.infer<typeof outcomeSchema>;

const OUTCOME_JSON_SCHEMA = {
  name: "review_outcome",
  schema: z.toJSONSchema(outcomeSchema) as Record<string, unknown>,
};

const TRANSCRIPT_CHAR_LIMIT = 8000;

const CLOSE_INSTRUCTIONS = `You summarize a finished review conversation between J.A.R.V.I.S. and its user into a structured outcome. Ground every item in what was actually said — no invention, no padding. Style: calm, dry, literal; short concrete phrases, no exclamation marks.
- wins: what went well this period (2-5 items, fewer if the transcript is thin).
- struggles: what did not work or was hard (0-5 items).
- adjustments: concrete changes that were proposed or agreed (0-5 items).
- focusNextWeek: ONE sentence naming the single most important focus for the next period.
Output only the JSON object matching the schema.`;

function partText(part: MessagePart): string {
  switch (part.type) {
    case "text":
      return part.text;
    case "tool_call":
      return `[proposed ${part.name}: ${JSON.stringify(part.args)}]`;
    case "tool_result":
      return `[tool result: ${JSON.stringify(part.result)}]`;
  }
}

export const POST = handler(
  async (request: Request, { params }: { params: Promise<{ conversationId: string }> }) => {
    const ctx = await requireAuth(request);
    const { conversationId } = await params;

    const conversation = await db.query.conversations.findFirst({
      where: eq(conversations.id, conversationId),
    });
    if (!conversation || conversation.userId !== ctx.userId) {
      throw new ApiError(404, "not_found", "Conversation not found");
    }
    if (conversation.kind !== "weekly_review" && conversation.kind !== "block_review") {
      throw new ApiError(400, "not_a_review", "Only review conversations can be closed");
    }

    const rows = await db.query.messages.findMany({
      where: eq(messages.conversationId, conversationId),
      orderBy: [asc(messages.createdAt)],
    });
    if (rows.length === 0) {
      throw new ApiError(409, "review_empty", "This review has no messages to summarize yet");
    }

    const transcript = rows
      .map((m) => `${m.role}: ${m.parts.map(partText).join("\n")}`)
      .join("\n\n")
      .slice(-TRANSCRIPT_CHAR_LIMIT);

    const call = await callModel<ReviewOutcome>({
      task: "weekly_review",
      instructions: CLOSE_INSTRUCTIONS,
      input: transcript,
      jsonSchema: OUTCOME_JSON_SCHEMA,
      overrides: ctx.settings.aiOverrides,
    });
    const outcome = outcomeSchema.parse(call.parsed);

    await db
      .update(conversations)
      .set({ outcome, updatedAt: new Date() })
      .where(eq(conversations.id, conversationId));

    return NextResponse.json({ outcome });
  },
);

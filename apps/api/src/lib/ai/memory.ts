// The AI's growing memory of the user: one durable fact per row, grouped by
// category. Facts arrive three ways — automatic extraction after every chat
// turn (this file), the save_memory tool during a conversation, and manual
// edits in the Memory screen. Extraction is best-effort: it runs after the
// response via next/server `after()` and must never break a chat turn.

import { asc, desc, eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/db/client";
import { memories, messages, type AiOverrides, type MessagePart } from "@/db/schema";
import { applyMemoryOps, memoryOpsSchema, type MemoryOp } from "./memory-ops";
import { callModel } from "./provider";

export type MemoryRow = typeof memories.$inferSelect;

const EXTRACTION_HISTORY = 6; // messages of context per extraction pass

// ---------- context block ----------

/** Markdown block for the system prompt; "" when nothing is stored yet. */
export async function memoryContextBlock(userId: string): Promise<string> {
  const rows = await db.query.memories.findMany({
    where: eq(memories.userId, userId),
    orderBy: [asc(memories.category), asc(memories.createdAt)],
  });
  if (rows.length === 0) return "";
  const byCategory = new Map<string, MemoryRow[]>();
  for (const row of rows) {
    const list = byCategory.get(row.category) ?? [];
    list.push(row);
    byCategory.set(row.category, list);
  }
  const lines: string[] = ["## What you have learned about the user (long-term memory)"];
  for (const [category, items] of byCategory) {
    lines.push(`${category}:`);
    for (const item of items) lines.push(`- ${item.content}`);
  }
  return lines.join("\n");
}

// ---------- extraction ----------

const EXTRACTION_INSTRUCTIONS = `You maintain J.A.R.V.I.S.'s long-term memory about exactly one user. Given the latest conversation excerpt and the current memory list, output operations that keep the memory accurate.

Extract ONLY durable facts about the user: who they are, work situation, relationships, health, appearance goals, preferences, recurring struggles, how they want to be spoken to.
NEVER store: tasks or todos (the app tracks those), one-off events, moods of the moment, anything the assistant said, or facts already stored (verbatim or paraphrased).
Prefer "update" over adding a near-duplicate. Use "delete" when the user contradicts a stored fact. Each content is ONE concise sentence, third person ("He ..."). It is normal to output zero ops.`;

function conversationExcerpt(rows: { role: string; parts: MessagePart[] }[]): string {
  return rows
    .map((m) => {
      const text = m.parts
        .filter((p): p is Extract<MessagePart, { type: "text" }> => p.type === "text")
        .map((p) => p.text)
        .join("\n");
      return text ? `${m.role}: ${text}` : null;
    })
    .filter(Boolean)
    .join("\n\n");
}

/**
 * Post-turn extraction. Swallows every error (logged) — a broken extraction
 * must never surface to the user or fail the request it trails.
 */
export async function extractMemories(
  userId: string,
  conversationId: string,
  overrides: AiOverrides,
): Promise<void> {
  try {
    const [history, existing] = await Promise.all([
      db.query.messages.findMany({
        where: eq(messages.conversationId, conversationId),
        orderBy: [desc(messages.createdAt)],
        limit: EXTRACTION_HISTORY,
      }),
      db.query.memories.findMany({ where: eq(memories.userId, userId) }),
    ]);
    history.reverse();
    const excerpt = conversationExcerpt(history);
    if (!excerpt) return;

    const call = await callModel<{ ops: MemoryOp[] }>({
      task: "memory_extraction",
      instructions: EXTRACTION_INSTRUCTIONS,
      input: JSON.stringify({
        conversation: excerpt,
        memories: existing.map((m) => ({ id: m.id, category: m.category, content: m.content })),
      }),
      jsonSchema: {
        name: "memory_ops",
        schema: z.toJSONSchema(memoryOpsSchema) as Record<string, unknown>,
      },
      overrides,
      maxOutputTokens: 4000,
    });

    const parsed = memoryOpsSchema.safeParse(call.parsed);
    if (!parsed.success) return;
    const resolved = applyMemoryOps(parsed.data.ops, new Set(existing.map((m) => m.id)));

    if (resolved.adds.length > 0) {
      await db.insert(memories).values(
        resolved.adds.map((add) => ({
          userId,
          category: add.category,
          content: add.content,
          source: "chat" as const,
          conversationId,
        })),
      );
    }
    for (const update of resolved.updates) {
      await db
        .update(memories)
        .set({
          content: update.content,
          ...(update.category ? { category: update.category } : {}),
          updatedAt: new Date(),
        })
        .where(eq(memories.id, update.id));
    }
    if (resolved.deletes.length > 0) {
      await db.delete(memories).where(inArray(memories.id, resolved.deletes));
    }
  } catch (error) {
    console.error("Memory extraction failed (ignored):", error);
  }
}

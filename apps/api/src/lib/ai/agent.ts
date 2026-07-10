// The chat agent loop. Read tools execute inline; mutating tools short-circuit
// into proposed_actions cards (the model receives a synthetic "pending user
// confirmation" result so it can reference the card and keep going).
// Confirmation later executes the STORED args deterministically — the model
// is not re-invoked (see confirmProposedAction).

import { and, asc, desc, eq } from "drizzle-orm";
import { db } from "@/db/client";
import {
  conversations,
  messages,
  proposedActions,
  type MessagePart,
} from "@/db/schema";
import type { SettingsRow } from "../auth";
import { ApiError } from "../http";
import { buildChatContext } from "./context";
import { getClient, resolveAIConfig } from "./provider";
import { TASK_TIERS, type AITask } from "./tiers";
import {
  executeMutation,
  executeReadTool,
  isMutatingTool,
  isReadTool,
  openAIToolDefinitions,
  summarizeMutation,
  validateMutatingArgs,
  type ToolContext,
} from "./tools";

const MAX_ITERATIONS = 8;
const HISTORY_LIMIT = 30;

interface FunctionCallItem {
  type: "function_call";
  call_id: string;
  name: string;
  arguments: string;
}

export type ProposedActionRow = typeof proposedActions.$inferSelect;

export interface AgentEvents {
  onDelta: (text: string) => void;
  onToolStatus: (name: string, status: "running" | "done") => void;
  onAction: (action: ProposedActionRow) => void;
}

function partsToText(parts: MessagePart[]): string {
  return parts
    .map((part) => {
      switch (part.type) {
        case "text":
          return part.text;
        case "tool_call":
          return `[proposed ${part.name}: ${JSON.stringify(part.args)}]`;
        case "tool_result":
          return `[tool result: ${JSON.stringify(part.result)}]`;
      }
    })
    .join("\n");
}

export interface AgentTurnOptions {
  userId: string;
  settings: SettingsRow;
  conversationId: string;
  userText: string;
  /** Extra system context, e.g. weekly-review seeding. */
  extraInstructions?: string;
  task?: AITask;
}

export async function runAgentTurn(
  options: AgentTurnOptions,
  events: AgentEvents,
): Promise<{ assistantMessageId: string }> {
  const { userId, settings, conversationId } = options;
  const ctx: ToolContext = { userId, settings };

  const conversation = await db.query.conversations.findFirst({
    where: eq(conversations.id, conversationId),
  });
  if (!conversation || conversation.userId !== userId) {
    throw new ApiError(404, "not_found", "Conversation not found");
  }

  const history = await db.query.messages.findMany({
    where: eq(messages.conversationId, conversationId),
    orderBy: [desc(messages.createdAt)],
    limit: HISTORY_LIMIT,
  });
  history.reverse();

  const [userMessage] = await db
    .insert(messages)
    .values({ conversationId, role: "user", parts: [{ type: "text", text: options.userText }] })
    .returning();
  void userMessage;

  const [assistantMessage] = await db
    .insert(messages)
    .values({ conversationId, role: "assistant", parts: [] })
    .returning();
  if (!assistantMessage) throw new ApiError(500, "internal_error", "Could not create message");

  const instructions = [
    await buildChatContext(userId, settings),
    options.extraInstructions ?? "",
  ]
    .filter(Boolean)
    .join("\n\n");

  const config = resolveAIConfig(settings.aiOverrides);
  const task: AITask = options.task ?? "chat";
  const tier = TASK_TIERS[task];
  const client = getClient(config);
  const tools = openAIToolDefinitions();

  type InputItem = Record<string, unknown>;
  let input: InputItem[] = [
    ...history.map((m) => ({
      role: m.role === "assistant" ? "assistant" : "user",
      content: m.role === "tool" ? `[tool] ${partsToText(m.parts)}` : partsToText(m.parts),
    })),
    { role: "user", content: options.userText },
  ];
  let previousResponseId: string | null = null;

  const collectedParts: MessagePart[] = [];
  let collectedText = "";
  let turnError: unknown = null;

  try {
    let lastHadFunctionCalls = false;
    for (let iteration = 0; iteration < MAX_ITERATIONS; iteration++) {
      const stream: AsyncIterable<
        import("openai/resources/responses/responses").ResponseStreamEvent
      > = await client.responses.create({
        model: config.models[tier],
        instructions,
        input: input as never,
        tools: tools as never,
        reasoning: { effort: config.efforts[tier] as never },
        max_output_tokens: 8000,
        stream: true,
        ...(previousResponseId ? { previous_response_id: previousResponseId } : {}),
      });

      let response: import("openai/resources/responses/responses").Response | null = null;
      let incomplete = false;
      for await (const event of stream) {
        if (event.type === "response.output_text.delta") {
          collectedText += event.delta;
          events.onDelta(event.delta);
        } else if (event.type === "response.completed") {
          response = event.response;
        } else if (event.type === "response.incomplete") {
          // Truncated (e.g. max_output_tokens) — the streamed text was
          // already shown, so treat the output as final instead of failing.
          response = event.response;
          incomplete = true;
        }
      }
      if (!response) throw new ApiError(502, "ai_stream_incomplete", "The model stream ended unexpectedly");
      previousResponseId = response.id;

      if (incomplete) break;

      const functionCalls = response.output.filter(
        (item): item is FunctionCallItem => item.type === "function_call",
      ) as FunctionCallItem[];
      lastHadFunctionCalls = functionCalls.length > 0;

      if (functionCalls.length === 0) break;

      const outputs: InputItem[] = [];
      for (const call of functionCalls) {
        let rawArgs: unknown;
        try {
          rawArgs = JSON.parse(call.arguments);
        } catch {
          outputs.push(functionOutput(call.call_id, { error: "malformed arguments" }));
          continue;
        }

        if (isReadTool(call.name)) {
          events.onToolStatus(call.name, "running");
          try {
            const result = await executeReadTool(ctx, call.name, rawArgs);
            collectedParts.push({ type: "tool_call", callId: call.call_id, name: call.name, args: rawArgs });
            collectedParts.push({ type: "tool_result", callId: call.call_id, result });
            outputs.push(functionOutput(call.call_id, result));
          } catch (error) {
            outputs.push(functionOutput(call.call_id, { error: errorMessage(error) }));
          }
          events.onToolStatus(call.name, "done");
        } else if (isMutatingTool(call.name)) {
          try {
            const args = validateMutatingArgs(call.name, rawArgs);
            const summary = await summarizeMutation(ctx, call.name, args);
            const [action] = await db
              .insert(proposedActions)
              .values({
                userId,
                conversationId,
                messageId: assistantMessage.id,
                toolName: call.name,
                args,
                summary,
              })
              .returning();
            if (action) {
              events.onAction(action);
              collectedParts.push({ type: "tool_call", callId: call.call_id, name: call.name, args });
              outputs.push(
                functionOutput(call.call_id, {
                  status: "pending_user_confirmation",
                  actionId: action.id,
                  summary,
                }),
              );
            }
          } catch (error) {
            outputs.push(functionOutput(call.call_id, { error: errorMessage(error) }));
          }
        } else {
          outputs.push(functionOutput(call.call_id, { error: `unknown tool ${call.name}` }));
        }
      }

      // Chain: only the outputs are sent; previous_response_id carries the rest.
      input = outputs;
    }

    // Ran out of iterations with the model still asking for tools — make sure
    // the persisted message is never empty.
    if (lastHadFunctionCalls && !collectedText) {
      collectedParts.push({ type: "text", text: "(stopped: too many tool steps)" });
    }
  } catch (error) {
    turnError = error;
    throw error;
  } finally {
    // Always persist whatever was collected — a mid-stream throw or client
    // disconnect must not lose partial text/tool parts.
    if (collectedText) collectedParts.push({ type: "text", text: collectedText });
    if (collectedParts.length === 0 && turnError) {
      collectedParts.push({ type: "text", text: "— interrupted" });
    }
    await db
      .update(messages)
      .set({ parts: collectedParts })
      .where(eq(messages.id, assistantMessage.id));
    await db
      .update(conversations)
      .set({ updatedAt: new Date() })
      .where(eq(conversations.id, conversationId));
  }

  // First exchange in a plain chat → generate a short title (best effort).
  if (!conversation.title && conversation.kind === "chat") {
    try {
      const title = await client.responses.create({
        model: config.models.fast,
        instructions: "Reply with a 2-5 word title for this conversation. No quotes, no punctuation.",
        input: options.userText.slice(0, 500),
        reasoning: { effort: "low" as never },
        max_output_tokens: 100,
      });
      const text = (title.output_text ?? "").trim().slice(0, 60);
      if (text) {
        await db.update(conversations).set({ title: text }).where(eq(conversations.id, conversationId));
      }
    } catch {
      // Title generation is cosmetic — never fail the turn over it.
    }
  }

  return { assistantMessageId: assistantMessage.id };
}

function functionOutput(callId: string, output: unknown) {
  return { type: "function_call_output", call_id: callId, output: JSON.stringify(output) };
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

// ---------- confirm / reject ----------

const ACTION_EXPIRY_MS = 24 * 60 * 60 * 1000;

export async function loadAction(userId: string, actionId: string): Promise<ProposedActionRow> {
  const action = await db.query.proposedActions.findFirst({
    where: eq(proposedActions.id, actionId),
  });
  if (!action || action.userId !== userId) throw new ApiError(404, "not_found", "Action not found");
  return action;
}

async function appendToolMessage(conversationId: string, text: string) {
  await db.insert(messages).values({
    conversationId,
    role: "tool",
    parts: [{ type: "text", text }],
  });
  await db.update(conversations).set({ updatedAt: new Date() }).where(eq(conversations.id, conversationId));
}

export async function confirmProposedAction(
  ctx: ToolContext,
  actionId: string,
): Promise<ProposedActionRow> {
  const action = await loadAction(ctx.userId, actionId);
  if (action.status !== "proposed") {
    throw new ApiError(409, "action_resolved", `Action is already ${action.status}`);
  }
  if (Date.now() - action.createdAt.getTime() > ACTION_EXPIRY_MS) {
    await db
      .update(proposedActions)
      .set({ status: "expired", resolvedAt: new Date() })
      .where(eq(proposedActions.id, actionId));
    throw new ApiError(410, "action_expired", "This proposal is older than 24 hours — ask again");
  }
  if (!isMutatingTool(action.toolName)) {
    throw new ApiError(500, "internal_error", "Stored action references an unknown tool");
  }

  // Atomic claim: only one concurrent confirm can flip proposed → executed,
  // so the mutation never runs twice.
  const [claimed] = await db
    .update(proposedActions)
    .set({ status: "executed", resolvedAt: new Date() })
    .where(and(eq(proposedActions.id, actionId), eq(proposedActions.status, "proposed")))
    .returning();
  if (!claimed) {
    const current = await loadAction(ctx.userId, actionId);
    if (current.status === "expired") {
      throw new ApiError(410, "action_expired", "This proposal is older than 24 hours — ask again");
    }
    throw new ApiError(409, "action_resolved", `Action is already ${current.status}`);
  }

  let result: unknown;
  try {
    result = await executeMutation(ctx, action.toolName, action.args);
  } catch (error) {
    // Execution failed — release the claim so the user can retry.
    await db
      .update(proposedActions)
      .set({ status: "proposed", resolvedAt: null })
      .where(eq(proposedActions.id, actionId));
    throw error;
  }
  const [updated] = await db
    .update(proposedActions)
    .set({ result })
    .where(eq(proposedActions.id, actionId))
    .returning();
  await appendToolMessage(
    action.conversationId,
    `Action confirmed and executed: ${action.summary}. Result: ${JSON.stringify(result)}`,
  );
  return updated!;
}

export async function rejectProposedAction(userId: string, actionId: string): Promise<ProposedActionRow> {
  const action = await loadAction(userId, actionId);
  if (action.status !== "proposed") {
    throw new ApiError(409, "action_resolved", `Action is already ${action.status}`);
  }
  const [updated] = await db
    .update(proposedActions)
    .set({ status: "rejected", resolvedAt: new Date() })
    .where(eq(proposedActions.id, actionId))
    .returning();
  await appendToolMessage(action.conversationId, `Action dismissed by the user: ${action.summary}`);
  return updated!;
}

/** Pending actions for a conversation, expiring stale ones on read. */
export async function pendingActions(conversationId: string): Promise<ProposedActionRow[]> {
  const rows = await db.query.proposedActions.findMany({
    where: eq(proposedActions.conversationId, conversationId),
    orderBy: [asc(proposedActions.createdAt)],
  });
  const now = Date.now();
  for (const row of rows) {
    if (row.status === "proposed" && now - row.createdAt.getTime() > ACTION_EXPIRY_MS) {
      await db
        .update(proposedActions)
        .set({ status: "expired", resolvedAt: new Date() })
        .where(eq(proposedActions.id, row.id));
      row.status = "expired";
    }
  }
  return rows;
}

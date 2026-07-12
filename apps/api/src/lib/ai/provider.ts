// Env-driven OpenAI provider over the Responses API.
// Resolution order: settings.ai_overrides (DB) > env > defaults.
// Codex-subscription auth (`codex_oauth`) is a flagged experiment: when its
// tokens are missing or auth fails, we fall back to plain api_key mode.

import OpenAI from "openai";
import type { AiOverrides } from "@/db/schema";
import { ApiError } from "../http";
import { TASK_TIERS, type AITask, type Tier } from "./tiers";

export interface AIConfig {
  baseUrl: string;
  authMode: "api_key" | "codex_oauth";
  models: Record<Tier, string>;
  efforts: Record<Tier, string>;
}

const DEFAULT_MODEL = "gpt-5.6-luna"; // verified available 2026-07-10; env overrides

export function resolveAIConfig(overrides: AiOverrides = {}): AIConfig {
  return {
    baseUrl: overrides.baseUrl ?? process.env.AI_BASE_URL ?? "https://api.openai.com/v1",
    authMode: overrides.authMode ?? (process.env.AI_AUTH_MODE as AIConfig["authMode"]) ?? "api_key",
    models: {
      deep: overrides.deepModel ?? process.env.AI_MODEL_DEEP ?? DEFAULT_MODEL,
      fast: overrides.fastModel ?? process.env.AI_MODEL_FAST ?? DEFAULT_MODEL,
    },
    efforts: {
      deep: overrides.deepEffort ?? process.env.AI_EFFORT_DEEP ?? "high",
      fast: overrides.fastEffort ?? process.env.AI_EFFORT_FAST ?? "low",
    },
  };
}

function apiKey(config: AIConfig): string {
  if (config.authMode === "codex_oauth") {
    // Experiment not wired yet: fall back to api_key silently but observably.
    console.warn("AI_AUTH_MODE=codex_oauth not implemented — falling back to api_key");
  }
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new ApiError(500, "ai_not_configured", "OPENAI_API_KEY is not set");
  return key;
}

export function getClient(config: AIConfig): OpenAI {
  return new OpenAI({ apiKey: apiKey(config), baseURL: config.baseUrl });
}

export interface ModelCallOptions {
  task: AITask;
  instructions: string;
  /** User-turn input: plain text, or structured Responses-API items (vision). */
  input: string | Array<Record<string, unknown>>;
  previousResponseId?: string | null;
  /** When set, forces strict JSON-schema output and parses it. */
  jsonSchema?: { name: string; schema: Record<string, unknown> };
  overrides?: AiOverrides;
  maxOutputTokens?: number;
}

export interface ModelCallResult<T = unknown> {
  responseId: string;
  text: string;
  parsed: T | null;
  model: string;
}

export async function callModel<T = unknown>(options: ModelCallOptions): Promise<ModelCallResult<T>> {
  const config = resolveAIConfig(options.overrides);
  const tier = TASK_TIERS[options.task];
  const client = getClient(config);

  const response = await client.responses.create({
    model: config.models[tier],
    instructions: options.instructions,
    input: options.input as never,
    reasoning: { effort: config.efforts[tier] as never },
    max_output_tokens: options.maxOutputTokens ?? 16_000,
    ...(options.previousResponseId ? { previous_response_id: options.previousResponseId } : {}),
    ...(options.jsonSchema
      ? {
          text: {
            format: {
              type: "json_schema" as const,
              name: options.jsonSchema.name,
              schema: options.jsonSchema.schema,
              strict: true,
            },
          },
        }
      : {}),
  });

  const text = response.output_text ?? "";
  let parsed: T | null = null;
  if (options.jsonSchema) {
    try {
      parsed = JSON.parse(text) as T;
    } catch {
      throw new ApiError(502, "ai_bad_output", "The model returned malformed JSON");
    }
  }

  return { responseId: response.id, text, parsed, model: config.models[tier] };
}

// Which model tier each AI task runs on. Config, not code — change here, not
// at call sites. "deep" = high reasoning (slow, thorough), "fast" = low/minimal
// reasoning (snappy, cheaper).

export type Tier = "deep" | "fast";

export const TASK_TIERS = {
  weekly_review: "deep",
  block_review: "deep",
  chat: "fast",
  seeding: "fast",
  briefing: "fast",
  conversation_title: "fast",
  memory_extraction: "fast",
  checkin_commentary: "deep",
} as const satisfies Record<string, Tier>;

export type AITask = keyof typeof TASK_TIERS;

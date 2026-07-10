// Live AI smoke test — costs real tokens, so it only runs with RUN_AI=1:
//   ek run -- env RUN_AI=1 pnpm vitest run tests/integration/interview.ai.test.ts
// Verifies the strict JSON schema round-trips through the Responses API on the
// configured model (schema accepted, output parses and validates).

import { describe, expect, it } from "vitest";

const enabled = process.env.RUN_AI === "1" && !!process.env.OPENAI_API_KEY;

describe.skipIf(!enabled)("interview round · live model smoke test", () => {
  it("returns a valid first round through strict json_schema output", async () => {
    const { callModel } = await import("../../src/lib/ai/provider");
    const { roundSchema, questionSchema, normalizeRound } = await import("../../src/lib/ai/interview");
    const { z } = await import("zod");

    const call = await callModel({
      task: "interview_round",
      instructions:
        "You are an interviewer. Ask exactly one single_choice question about the user's morning routine with 3 concrete options. Set done=false, phase='About you', phaseIndex=0, result=null. Output only JSON matching the schema.",
      input: "Begin.",
      jsonSchema: {
        name: "interview_round",
        schema: z.toJSONSchema(roundSchema) as Record<string, unknown>,
      },
      // Keep the smoke test fast/cheap regardless of the deep tier's default.
      overrides: { deepEffort: "low" },
    });

    const round = normalizeRound(roundSchema.parse(call.parsed));
    expect(round.done).toBe(false);
    expect(round.questions.length).toBeGreaterThanOrEqual(1);
    const question = questionSchema.parse(round.questions[0]);
    expect(question.allowFreeText).toBe(true);
    expect(call.responseId).toMatch(/^resp/);
  }, 120_000);
});

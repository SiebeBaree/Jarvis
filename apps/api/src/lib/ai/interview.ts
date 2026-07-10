// Onboarding interview protocol. Each model turn returns strict JSON: either
// the next round of natively-rendered questions, or (done) the synthesized
// profile + vision draft + proposed 12-week plan. Nothing is persisted to the
// real domain tables until the user edits and approves via apply (apply-plan.ts).

import { and, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/db/client";
import { interviewSessions, type AiOverrides } from "@/db/schema";
import { ApiError } from "../http";
import { callModel } from "./provider";

// ---------- round output schema (strict JSON schema for the model) ----------

export const questionSchema = z.strictObject({
  id: z.string(),
  question: z.string(),
  type: z.enum(["single_choice", "multi_choice", "free_text", "scale"]),
  options: z.array(z.string()).nullable(), // null for free_text
  allowFreeText: z.boolean(), // instructed to always be true
  rationale: z.string().nullable(), // subtle helper text under the question
  skippable: z.boolean(),
  isFollowUp: z.boolean(),
});

export const planHabitSchema = z.strictObject({
  name: z.string(),
  icon: z.string().nullable(), // SF Symbol name
  type: z.enum(["daily", "multi_daily", "weekly_frequency"]),
  targetReps: z.number().int(),
  plannedDays: z.array(z.number().int()), // ISO weekdays, soft suggestions
});

export const planTaskSchema = z.strictObject({
  title: z.string(),
  notes: z.string().nullable(),
  dueOffsetDays: z.number().int().nullable(), // days from block start
  priority: z.enum(["low", "medium", "high"]),
});

export const planTacticSchema = z.strictObject({
  title: z.string(),
  fromWeek: z.number().int(),
  toWeek: z.number().int(),
});

export const planGoalSchema = z.strictObject({
  title: z.string(),
  description: z.string(),
  targetLine: z.string(), // one measurable sentence, e.g. "Bench 80 kg by week 12"
  areaIndex: z.number().int().nullable(), // index into result.areas
  tactics: z.array(planTacticSchema),
  habits: z.array(planHabitSchema),
  tasks: z.array(planTaskSchema),
});

export const interviewResultSchema = z.strictObject({
  profile: z.strictObject({
    values: z.array(z.string()),
    constraints: z.array(z.string()),
    schedule: z.string(),
    motivations: z.array(z.string()),
    context: z.string(),
  }),
  visionDraft: z.string(),
  areas: z.array(z.strictObject({ name: z.string(), emoji: z.string() })),
  plan: z.strictObject({
    blockTitle: z.string(),
    goals: z.array(planGoalSchema),
  }),
});

export const roundSchema = z.strictObject({
  done: z.boolean(),
  phase: z.string(),
  phaseIndex: z.number().int(), // 0-5, drives the dot-stepper
  questions: z.array(questionSchema), // empty when done
  result: interviewResultSchema.nullable(), // present only when done
});

export type InterviewRound = z.infer<typeof roundSchema>;
export type InterviewResult = z.infer<typeof interviewResultSchema>;

/**
 * Server-side guarantees the UI relies on, regardless of what the model set:
 * "write my own" is always available, and choice questions must have options.
 */
export function normalizeRound(round: InterviewRound): InterviewRound {
  return {
    ...round,
    phaseIndex: Math.min(Math.max(round.phaseIndex, 0), PHASES.length - 1),
    questions: round.questions.map((q) => ({
      ...q,
      allowFreeText: true,
      options:
        q.type === "single_choice" || q.type === "multi_choice" || q.type === "scale"
          ? (q.options ?? [])
          : null,
    })),
  };
}

const ROUND_JSON_SCHEMA = {
  name: "interview_round",
  schema: z.toJSONSchema(roundSchema) as Record<string, unknown>,
};

// ---------- answers (client → server → model) ----------

export const answerSchema = z.object({
  questionId: z.string(),
  selectedOptions: z.array(z.string()).default([]),
  freeText: z.string().max(4000).nullish(),
  skipped: z.boolean().default(false),
});
export const answersSchema = z.object({ answers: z.array(answerSchema).min(1) });
export type InterviewAnswer = z.infer<typeof answerSchema>;

// ---------- interviewer persona ----------

export const PHASES = [
  "About you",
  "Life areas",
  "Your vision",
  "This block's goals",
  "Habits & routines",
  "Wrap-up",
] as const;

const MAX_ROUNDS = 25;
const WRAP_UP_AFTER_ROUND = 22;

function interviewerInstructions(kind: string): string {
  return `You are J.A.R.V.I.S., a personal life assistant conducting a ${
    kind === "onboarding" ? "first, deep onboarding" : "focused follow-up"
  } interview. Your goal: understand this person well enough to design their next 12 weeks — then produce a concrete plan they will review and edit before anything is created.

VOICE & STYLE
- Calm, dry, precise. No exclamation marks, no hype, no therapy-speak.
- Literal and concrete (the user is autistic and prefers explicit, unambiguous wording). Never ask vague vibes-questions; every abstract question must ship concrete example options.
- One topic at a time. Depth over breadth, but at most ~3 follow-ups per topic.

INTERVIEW STRUCTURE — six phases, in order, reported via "phase" and "phaseIndex" (0-5):
${PHASES.map((p, i) => `${i}. ${p}`).join("\n")}
Announce nothing; just set the fields. Move to the next phase when the current one is understood. You control how many rounds each phase needs.

EVERY ROUND (done=false)
- 1 to 3 questions, each with a stable unique "id".
- Prefer single_choice/multi_choice with 3-6 concrete options drawn from what they already told you; "allowFreeText" is ALWAYS true (the UI always offers "write my own").
- "scale" questions use options like ["1","2","3","4","5"] with the meaning in the question text.
- Mark genuine follow-ups with isFollowUp=true. Mark optional/sensitive questions skippable=true.
- "rationale": one short line of why you ask, or null.

WHEN TO FINISH (done=true, questions=[], result set)
Finish when you can write a specific plan grounded in their answers — do not pad. In the final round produce "result":
- profile: values, constraints (time/energy/schedule realities), schedule (one paragraph), motivations, context (a dense summary of who they are — you will rely on this for months).
- visionDraft: their dream life in 2-3 first-person paragraphs, in their own concepts, no dates.
- areas: 2-5 life areas with a single emoji each, derived from THEM (not a template).
- plan.blockTitle: short and specific (e.g. "Q3 — Ship and Shred").
- plan.goals: 2-4 goals. Each: measurable targetLine; tactics (1-4, week ranges within 1-12) = recurring strategy moves; habits using EXACTLY one of the three types — "daily" (targetReps 1), "multi_daily" (targetReps 2-10 per day), "weekly_frequency" (targetReps 1-7 per week, plannedDays = suggested ISO weekdays 1-7, never enforced); tasks = 1-5 one-off starters with dueOffsetDays (0-83) from block start and a priority.
Everything must be traceable to their answers. Nothing generic.

LANGUAGE: mirror the user's language (default English).
OUTPUT: only the JSON object matching the provided schema.`;
}

// ---------- session flow ----------

export type InterviewSessionRow = typeof interviewSessions.$inferSelect;

function transcriptRounds(session: InterviewSessionRow): number {
  return session.transcript.length;
}

export async function startInterview(
  userId: string,
  kind: string,
  overrides: AiOverrides,
): Promise<{ session: InterviewSessionRow; round: InterviewRound }> {
  // Abandon any previous active session of the same kind.
  await db
    .update(interviewSessions)
    .set({ status: "abandoned" })
    .where(and(eq(interviewSessions.userId, userId), eq(interviewSessions.status, "active")));

  const call = await callModel<InterviewRound>({
    task: "interview_round",
    instructions: interviewerInstructions(kind),
    input:
      "Begin the interview. Round 1: open with phase 0 (About you) — concrete questions about who they are, what they do, and how their days actually look.",
    jsonSchema: ROUND_JSON_SCHEMA,
    overrides,
  });

  const round = normalizeRound(roundSchema.parse(call.parsed));
  const [session] = await db
    .insert(interviewSessions)
    .values({
      userId,
      kind,
      status: "active",
      transcript: [{ round: 1, phase: round.phase, phaseIndex: round.phaseIndex, questions: round.questions }],
      providerResponseId: call.responseId,
    })
    .returning();
  if (!session) throw new ApiError(500, "internal_error", "Could not create interview session");
  return { session, round };
}

export async function answerInterviewRound(
  session: InterviewSessionRow,
  answers: InterviewAnswer[],
  overrides: AiOverrides,
): Promise<{ round: InterviewRound; session: InterviewSessionRow }> {
  if (session.status !== "active") {
    throw new ApiError(409, "interview_not_active", "This interview is no longer active");
  }

  const roundNumber = transcriptRounds(session);
  const wrapUpNudge =
    roundNumber >= MAX_ROUNDS
      ? "\n\nHARD LIMIT REACHED: you MUST set done=true this round and produce the result from what you know."
      : roundNumber >= WRAP_UP_AFTER_ROUND
        ? "\n\nYou are near the round limit. Ask only what is truly essential, then finish."
        : "";

  const call = await callModel<InterviewRound>({
    task: "interview_round",
    instructions: interviewerInstructions(session.kind),
    input: JSON.stringify({ answers }) + wrapUpNudge,
    previousResponseId: session.providerResponseId,
    jsonSchema: ROUND_JSON_SCHEMA,
    overrides,
  });

  const round = normalizeRound(roundSchema.parse(call.parsed));

  // Record the answers onto the previous transcript entry, then the new round.
  const transcript = [...session.transcript] as Record<string, unknown>[];
  const last = transcript[transcript.length - 1];
  if (last) last.answers = answers;
  if (!round.done) {
    transcript.push({
      round: roundNumber + 1,
      phase: round.phase,
      phaseIndex: round.phaseIndex,
      questions: round.questions,
    });
  }

  const [updated] = await db
    .update(interviewSessions)
    .set({
      transcript,
      providerResponseId: call.responseId,
      ...(round.done
        ? { status: "completed" as const, result: round.result, completedAt: new Date() }
        : {}),
    })
    .where(eq(interviewSessions.id, session.id))
    .returning();

  return { round, session: updated ?? session };
}

// Live end-to-end interview pipeline test (costs a couple of low-effort model
// calls). Gated: ek run -- env RUN_AI=1 pnpm vitest run tests/integration/interview.e2e.test.ts
//
// start → answer round 1 → (transcript padded to the hard round limit) →
// forced completion with a full result → applyPlan → assert created rows →
// clean up EVERYTHING (block/goals/tactics/habits/tasks/areas/vision/profile/session).

import { afterAll, beforeAll, describe, expect, it } from "vitest";

const enabled = process.env.RUN_AI === "1" && !!process.env.OPENAI_API_KEY && !!process.env.DATABASE_URL;

describe.skipIf(!enabled)("interview → plan → apply · live e2e", () => {
  let db: typeof import("../../src/db/client").db;
  let schema: typeof import("../../src/db/schema");
  let drizzle: typeof import("drizzle-orm");
  let interview: typeof import("../../src/lib/ai/interview");
  let applyPlanModule: typeof import("../../src/lib/ai/apply-plan");
  let snapshot: typeof import("../../src/lib/scoring/snapshot");

  let userId: string;
  let settings: import("../../src/lib/auth").SettingsRow;
  let sessionId: string | null = null;
  let createdBlockId: string | null = null;

  // Preserve any pre-existing vision/profile so cleanup can restore reality.
  let hadVision = false;
  let hadProfile = false;
  let preexistingAreaIds = new Set<string>();

  const OVERRIDES = { deepEffort: "low" as const };

  beforeAll(async () => {
    db = (await import("../../src/db/client")).db;
    schema = await import("../../src/db/schema");
    drizzle = await import("drizzle-orm");
    interview = await import("../../src/lib/ai/interview");
    applyPlanModule = await import("../../src/lib/ai/apply-plan");
    snapshot = await import("../../src/lib/scoring/snapshot");

    const user = await db.query.users.findFirst();
    if (!user) throw new Error("No user registered");
    userId = user.id;
    const settingsRow = await db.query.settings.findFirst({
      where: drizzle.eq(schema.settings.userId, userId),
    });
    if (!settingsRow) throw new Error("No settings row");
    settings = settingsRow;

    hadVision = !!(await db.query.vision.findFirst({ where: drizzle.eq(schema.vision.userId, userId) }));
    hadProfile = !!(await db.query.userProfile.findFirst({
      where: drizzle.eq(schema.userProfile.userId, userId),
    }));
    preexistingAreaIds = new Set(
      (await db.query.areas.findMany({ where: drizzle.eq(schema.areas.userId, userId) })).map((a) => a.id),
    );
  });

  afterAll(async () => {
    const { eq, and, inArray, notInArray } = drizzle;
    if (createdBlockId) {
      const blockGoals = await db.query.goals.findMany({
        where: eq(schema.goals.blockId, createdBlockId),
      });
      const goalIds = blockGoals.map((g) => g.id);
      if (goalIds.length > 0) {
        await db.delete(schema.habits).where(inArray(schema.habits.goalId, goalIds));
        await db.delete(schema.tasks).where(inArray(schema.tasks.goalId, goalIds));
      }
      await db.delete(schema.blocks).where(eq(schema.blocks.id, createdBlockId)); // cascades goals → tactics
    }
    // Areas created by this test run only.
    const areasNow = await db.query.areas.findMany({ where: eq(schema.areas.userId, userId) });
    const testAreaIds = areasNow.filter((a) => !preexistingAreaIds.has(a.id)).map((a) => a.id);
    if (testAreaIds.length > 0) {
      await db.delete(schema.areas).where(inArray(schema.areas.id, testAreaIds));
    }
    if (!hadVision) await db.delete(schema.vision).where(eq(schema.vision.userId, userId));
    if (!hadProfile) await db.delete(schema.userProfile).where(eq(schema.userProfile.userId, userId));
    if (sessionId) {
      await db.delete(schema.interviewSessions).where(eq(schema.interviewSessions.id, sessionId));
    }
    // Regenerate today's score from real data only.
    await snapshot.recomputeDay(userId, settings, snapshot.todayKey(settings));
    void and;
    void notInArray;
  });

  it("runs the full pipeline", async () => {
    // Round 1.
    const started = await interview.startInterview(userId, "onboarding", OVERRIDES);
    sessionId = started.session.id;
    expect(started.round.done).toBe(false);
    expect(started.round.questions.length).toBeGreaterThan(0);

    // Answer round 1 plausibly.
    const answers = started.round.questions.map((q) => ({
      questionId: q.id,
      selectedOptions: q.options?.length ? [q.options[0]!] : [],
      freeText:
        "I run a security software startup, go to the gym four times a week, and want more discipline in deep work.",
      skipped: false,
    }));

    // Pad the transcript to the hard limit so the NEXT answer forces done=true
    // (exercises the runaway guard + the full result schema in one cheap call).
    const padded = [
      ...started.session.transcript,
      ...Array.from({ length: 25 }, (_, i) => ({ round: i + 2, padded: true })),
    ];
    await db
      .update(schema.interviewSessions)
      .set({ transcript: padded })
      .where(drizzle.eq(schema.interviewSessions.id, sessionId));
    const session = await db.query.interviewSessions.findFirst({
      where: drizzle.eq(schema.interviewSessions.id, sessionId),
    });

    const final = await interview.answerInterviewRound(session!, answers, OVERRIDES);
    expect(final.round.done).toBe(true);
    expect(final.round.result).not.toBeNull();
    const result = final.round.result!;
    expect(result.plan.goals.length).toBeGreaterThanOrEqual(1);
    expect(result.areas.length).toBeGreaterThanOrEqual(1);

    // Apply exactly as the client would (payload = result, default start date).
    const applied = await applyPlanModule.applyPlan(userId, settings, sessionId, {
      vision: result.visionDraft,
      profile: result.profile,
      areas: result.areas,
      block: { title: result.plan.blockTitle, startDate: null },
      goals: result.plan.goals,
    });
    createdBlockId = applied.blockId;

    const block = await db.query.blocks.findFirst({
      where: drizzle.eq(schema.blocks.id, applied.blockId),
    });
    expect(block).toBeTruthy();
    // Monday-aligned 13-week block.
    const { isoWeekday, diffDays } = await import("../../src/lib/daykey");
    expect(isoWeekday(block!.startDate)).toBe(1);
    expect(diffDays(block!.startDate, block!.endDate)).toBe(90);

    const createdGoals = await db.query.goals.findMany({
      where: drizzle.eq(schema.goals.blockId, applied.blockId),
    });
    expect(createdGoals.length).toBe(result.plan.goals.length);

    const sessionAfter = await db.query.interviewSessions.findFirst({
      where: drizzle.eq(schema.interviewSessions.id, sessionId),
    });
    expect(sessionAfter?.status).toBe("applied");
  }, 300_000);
});

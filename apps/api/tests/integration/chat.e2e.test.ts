// Live chat-agent pipeline test (fast tier — cheap). Gated:
//   ek run -- env RUN_AI=1 pnpm vitest run tests/integration/chat.e2e.test.ts
// Covers: agent turn with a mutating tool → proposed_actions card → confirm
// executes stored args → tool message appended; wrap-up generation + cache.

import { afterAll, beforeAll, describe, expect, it } from "vitest";

const enabled = process.env.RUN_AI === "1" && !!process.env.OPENAI_API_KEY && !!process.env.DATABASE_URL;

describe.skipIf(!enabled)("chat agent → action card → confirm · live e2e", () => {
  let db: typeof import("../../src/db/client").db;
  let schema: typeof import("../../src/db/schema");
  let drizzle: typeof import("drizzle-orm");
  let agent: typeof import("../../src/lib/ai/agent");
  let snapshot: typeof import("../../src/lib/scoring/snapshot");

  let userId: string;
  let settings: import("../../src/lib/auth").SettingsRow;
  let conversationId: string | null = null;
  let createdTaskId: string | null = null;

  beforeAll(async () => {
    db = (await import("../../src/db/client")).db;
    schema = await import("../../src/db/schema");
    drizzle = await import("drizzle-orm");
    agent = await import("../../src/lib/ai/agent");
    snapshot = await import("../../src/lib/scoring/snapshot");

    const user = await db.query.users.findFirst();
    if (!user) throw new Error("No user registered");
    userId = user.id;
    const settingsRow = await db.query.settings.findFirst({
      where: drizzle.eq(schema.settings.userId, userId),
    });
    if (!settingsRow) throw new Error("No settings row");
    settings = settingsRow;
  });

  afterAll(async () => {
    const { eq, and } = drizzle;
    if (createdTaskId) {
      await db.delete(schema.tasks).where(eq(schema.tasks.id, createdTaskId));
    }
    if (conversationId) {
      await db.delete(schema.conversations).where(eq(schema.conversations.id, conversationId));
    }
    const today = snapshot.todayKey(settings);
    await db
      .delete(schema.briefings)
      .where(and(eq(schema.briefings.userId, userId), eq(schema.briefings.dayKey, today)));
    await snapshot.recomputeDay(userId, settings, today);
  });

  it("proposes a create_task card and executes it on confirm", async () => {
    const [conversation] = await db
      .insert(schema.conversations)
      .values({ userId, kind: "chat" })
      .returning();
    conversationId = conversation!.id;

    const actions: import("../../src/lib/ai/agent").ProposedActionRow[] = [];
    let deltas = "";
    await agent.runAgentTurn(
      {
        userId,
        settings,
        conversationId: conversation!.id,
        userText:
          'Create a task titled "E2E probe task" due today with medium priority. Propose it immediately — no clarifying questions.',
      },
      {
        onDelta: (t) => {
          deltas += t;
        },
        onToolStatus: () => {},
        onAction: (a) => actions.push(a),
      },
    );

    expect(actions.length).toBeGreaterThanOrEqual(1);
    const proposal = actions.find((a) => a.toolName === "create_task");
    expect(proposal).toBeTruthy();
    expect(proposal!.status).toBe("proposed");
    expect(proposal!.summary).toContain("E2E probe task");

    // Nothing was created before confirmation.
    const before = await db.query.tasks.findMany({
      where: drizzle.and(
        drizzle.eq(schema.tasks.userId, userId),
        drizzle.eq(schema.tasks.title, "E2E probe task"),
      ),
    });
    expect(before.length).toBe(0);

    // Confirm → deterministic execution of the stored args.
    const executed = await agent.confirmProposedAction({ userId, settings }, proposal!.id);
    expect(executed.status).toBe("executed");
    createdTaskId = (executed.result as { taskId?: string })?.taskId ?? null;
    expect(createdTaskId).toBeTruthy();

    const created = await db.query.tasks.findFirst({
      where: drizzle.eq(schema.tasks.id, createdTaskId!),
    });
    expect(created?.title).toBe("E2E probe task");
    expect(created?.dueDate).toBe(snapshot.todayKey(settings));

    // A tool message recorded the outcome for the model's next turn.
    const toolMessages = await db.query.messages.findMany({
      where: drizzle.eq(schema.messages.conversationId, conversation!.id),
    });
    expect(toolMessages.some((m) => m.role === "tool")).toBe(true);

    // Double-confirm is rejected.
    await expect(agent.confirmProposedAction({ userId, settings }, proposal!.id)).rejects.toThrow();

    void deltas; // streaming text is model-dependent; not asserted
  }, 240_000);

  it("generates and caches the evening wrap-up", async () => {
    const { getWrapup } = await import("../../src/lib/ai/briefing");
    const first = await getWrapup(userId, settings);
    expect(first.content.length).toBeGreaterThan(20);
    const second = await getWrapup(userId, settings);
    expect(second.content).toBe(first.content); // cache hit, no regeneration
  }, 120_000);
});

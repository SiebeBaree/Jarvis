// Stage 1 integration test against a REAL database (Neon dev branch).
// Only runs when RUN_INTEGRATION=1 and DATABASE_URL are set:
//   ek run -- env RUN_INTEGRATION=1 pnpm vitest run tests/integration/stage1.db.test.ts
//
// Creates clearly-marked test rows for the existing user, exercises the
// scoring snapshot layer end-to-end (week reconciliation, late retro-credit,
// renormalization), and deletes everything it created in afterAll.

import { afterAll, beforeAll, describe, expect, it } from "vitest";

const enabled = process.env.RUN_INTEGRATION === "1" && !!process.env.DATABASE_URL;

describe.skipIf(!enabled)("stage 1 · real-database scoring integration", () => {
  // Dynamic imports so the module graph (db client throws without DATABASE_URL)
  // is only loaded when the test actually runs.
  let db: typeof import("../../src/db/client").db;
  let schema: typeof import("../../src/db/schema");
  let snapshot: typeof import("../../src/lib/scoring/snapshot");
  let daykey: typeof import("../../src/lib/daykey");
  let drizzle: typeof import("drizzle-orm");

  let userId: string;
  let settings: import("../../src/lib/auth").SettingsRow;

  // All test data lives in a completed past week + yesterday, so the user's
  // real "today" row is never touched.
  let lastWeekMonday: string;
  let yesterday: string;
  const createdHabitIds: string[] = [];
  const createdTaskIds: string[] = [];
  const touchedScoreDays: string[] = [];

  beforeAll(async () => {
    db = (await import("../../src/db/client")).db;
    schema = await import("../../src/db/schema");
    snapshot = await import("../../src/lib/scoring/snapshot");
    daykey = await import("../../src/lib/daykey");
    drizzle = await import("drizzle-orm");

    const user = await db.query.users.findFirst();
    if (!user) throw new Error("No user in the database — register first");
    userId = user.id;

    const settingsRow = await db.query.settings.findFirst({
      where: drizzle.eq(schema.settings.userId, userId),
    });
    if (!settingsRow) throw new Error("No settings row");
    settings = settingsRow;

    const today = snapshot.todayKey(settings);
    yesterday = daykey.addDays(today, -1);
    lastWeekMonday = daykey.addDays(daykey.weekStart(today), -7);
  });

  afterAll(async () => {
    if (!userId) return;
    const { inArray, and, eq } = drizzle;
    if (createdHabitIds.length > 0) {
      // Cascades habit_completions.
      await db.delete(schema.habits).where(inArray(schema.habits.id, createdHabitIds));
    }
    if (createdTaskIds.length > 0) {
      await db.delete(schema.tasks).where(inArray(schema.tasks.id, createdTaskIds));
    }
    await db
      .delete(schema.moodEntries)
      .where(and(eq(schema.moodEntries.userId, userId), eq(schema.moodEntries.dayKey, yesterday)));
    if (touchedScoreDays.length > 0) {
      await db
        .delete(schema.dailyScores)
        .where(
          and(
            eq(schema.dailyScores.userId, userId),
            inArray(schema.dailyScores.dayKey, touchedScoreDays),
          ),
        );
    }
  });

  it("reconciles a back-loaded gym week to full credit on every day", async () => {
    const [gym] = await db
      .insert(schema.habits)
      .values({
        userId,
        name: "[test] gym",
        type: "weekly_frequency",
        targetReps: 5,
        plannedDays: [1, 2, 4, 5, 6],
        startDate: lastWeekMonday,
      })
      .returning();
    createdHabitIds.push(gym!.id);

    // 5 sessions Tue–Sat, NONE on the planned Monday.
    for (let offset = 1; offset <= 5; offset++) {
      await db.insert(schema.habitCompletions).values({
        userId,
        habitId: gym!.id,
        dayKey: daykey.addDays(lastWeekMonday, offset),
      });
    }

    const monday = await snapshot.recomputeDay(userId, settings, lastWeekMonday);
    touchedScoreDays.push(lastWeekMonday);

    const gymEntry = monday.breakdown.habits.find((h) => h.habitId === gym!.id);
    expect(gymEntry?.reconciled).toBe(true);
    expect(gymEntry?.credit).toBe(1); // skipped Monday costs nothing
    expect(monday.isFinal).toBe(true); // the week has fully ended
  });

  it("scores partial multi-rep habits proportionally with renormalization", async () => {
    const [teeth] = await db
      .insert(schema.habits)
      .values({
        userId,
        name: "[test] brush teeth",
        type: "multi_daily",
        targetReps: 2,
        startDate: lastWeekMonday,
      })
      .returning();
    createdHabitIds.push(teeth!.id);

    const wednesday = daykey.addDays(lastWeekMonday, 2);
    await db.insert(schema.habitCompletions).values({ userId, habitId: teeth!.id, dayKey: wednesday });

    const day = await snapshot.recomputeDay(userId, settings, wednesday);
    touchedScoreDays.push(wednesday);

    const teethEntry = day.breakdown.habits.find((h) => h.habitId === teeth!.id);
    expect(teethEntry?.credit).toBe(0.5); // 1 of 2 reps

    // No tasks due, no mood that day → only the habit weight applies.
    expect(day.taskPoints).toBeNull();
    expect(day.feelPoints).toBeNull();
    expect(day.applicableWeight).toBe(settings.scoreWeights.habits);
  });

  it("retro-credits a late-completed task on its original due date", async () => {
    const [task] = await db
      .insert(schema.tasks)
      .values({ userId, title: "[test] overdue task", dueDate: yesterday })
      .returning();
    createdTaskIds.push(task!.id);

    const before = await snapshot.recomputeDay(userId, settings, yesterday);
    touchedScoreDays.push(yesterday);
    expect(before.breakdown.tasks.find((t) => t.taskId === task!.id)?.credit).toBe(0);

    // Complete it "today" — after its due date.
    await db
      .update(schema.tasks)
      .set({ status: "done", completedAt: new Date() })
      .where(drizzle.eq(schema.tasks.id, task!.id));

    const after = await snapshot.recomputeDay(userId, settings, yesterday);
    const entry = after.breakdown.tasks.find((t) => t.taskId === task!.id);
    expect(entry?.credit).toBe(1);
    expect(entry?.late).toBe(true);
  });

  it("recomputes a day when mood is backfilled", async () => {
    await db
      .insert(schema.moodEntries)
      .values({ userId, dayKey: yesterday, value: 60 })
      .onConflictDoUpdate({
        target: [schema.moodEntries.userId, schema.moodEntries.dayKey],
        set: { value: 60 },
      });

    const day = await snapshot.recomputeDay(userId, settings, yesterday);
    expect(day.feelPoints).toBeCloseTo(settings.scoreWeights.feel * 0.6, 5);
    expect(day.applicableWeight).toBeGreaterThan(settings.scoreWeights.habits);
  });
});

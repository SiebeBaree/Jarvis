// Notification queries against a REAL database (the shared Neon instance).
// Only runs when RUN_INTEGRATION=1 and DATABASE_URL are set:
//   ek run -- env RUN_INTEGRATION=1 pnpm vitest run tests/integration/notifications.db.test.ts
//
// The message engine is covered by pure unit tests; what needs a database is
// the shape of the gathering queries and the dedupe claim the cron relies on.
// Everything it writes sits on a far-past dayKey and is deleted in afterAll, so
// the user's real days are never touched.

import { afterAll, beforeAll, describe, expect, it } from "vitest";

const enabled = process.env.RUN_INTEGRATION === "1" && !!process.env.DATABASE_URL;

describe.skipIf(!enabled)("notifications · real-database integration", () => {
  let db: typeof import("../../src/db/client").db;
  let schema: typeof import("../../src/db/schema");
  let data: typeof import("../../src/lib/notifications/data");
  let drizzle: typeof import("drizzle-orm");

  let userId: string;
  let settings: import("../../src/lib/auth").SettingsRow;

  // A date far enough back that no real entry can collide with it.
  const testDayKey = "2001-01-08";
  const createdDeviceIds: string[] = [];

  beforeAll(async () => {
    db = (await import("../../src/db/client")).db;
    schema = await import("../../src/db/schema");
    data = await import("../../src/lib/notifications/data");
    drizzle = await import("drizzle-orm");

    const user = await db.query.users.findFirst();
    if (!user) throw new Error("No user in the database — register first");
    userId = user.id;

    const settingsRow = await db.query.settings.findFirst({
      where: drizzle.eq(schema.settings.userId, userId),
    });
    if (!settingsRow) throw new Error("No settings row");
    settings = settingsRow;
  });

  afterAll(async () => {
    if (!userId) return;
    const { and, eq, inArray } = drizzle;
    await db
      .delete(schema.notificationLog)
      .where(
        and(
          eq(schema.notificationLog.userId, userId),
          eq(schema.notificationLog.dayKey, testDayKey),
        ),
      );
    if (createdDeviceIds.length > 0) {
      await db.delete(schema.devices).where(inArray(schema.devices.id, createdDeviceIds));
    }
  });

  it("gathers nudge data without error and returns sane shapes", async () => {
    const result = await data.gatherNudgeData(userId, settings, testDayKey);

    expect(result.dayKey).toBe(testDayKey);
    expect(typeof result.hasAnyMoodEntry).toBe("boolean");
    expect(Number.isInteger(result.openTasksToday)).toBe(true);
    expect(Number.isInteger(result.overdueTasks)).toBe(true);
    expect(result.openTasksToday).toBeGreaterThanOrEqual(0);
    // Every open task with a due date is in the past relative to 2001, so the
    // overdue count is the only one that can be non-zero for this dayKey.
    expect(result.openTasksToday).toBe(0);
    if (result.bestActiveStreak !== null) {
      expect(result.bestActiveStreak.days).toBeGreaterThan(0);
      expect(result.bestActiveStreak.habitName.length).toBeGreaterThan(0);
    }
  });

  it("reports no mood on a day that was never logged", async () => {
    expect(await data.hasMoodFor(userId, testDayKey)).toBe(false);
  });

  it("claims a day exactly once, which is what stops a double send", async () => {
    const claim = () =>
      db
        .insert(schema.notificationLog)
        .values({ userId, dayKey: testDayKey, kind: "checkin_nudge" })
        .onConflictDoNothing()
        .returning();

    const first = await claim();
    expect(first).toHaveLength(1);

    // A cron retry, or a developer curling the route, hits this branch.
    const second = await claim();
    expect(second).toHaveLength(0);
  });

  it("upserts a device on the token so re-registering does not duplicate it", async () => {
    const { and, eq } = drizzle;
    const token = "00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff";

    const insert = (environment: "sandbox" | "production") =>
      db
        .insert(schema.devices)
        .values({ userId, deviceToken: token, platform: "ios", environment })
        .onConflictDoUpdate({
          target: schema.devices.deviceToken,
          set: { userId, environment, lastSeenAt: new Date(), revokedAt: null },
        })
        .returning();

    const [created] = await insert("sandbox");
    expect(created).toBeDefined();
    if (created) createdDeviceIds.push(created.id);

    const [updated] = await insert("production");
    expect(updated?.id).toBe(created?.id);
    expect(updated?.environment).toBe("production");

    const rows = await db
      .select()
      .from(schema.devices)
      .where(and(eq(schema.devices.userId, userId), eq(schema.devices.deviceToken, token)));
    expect(rows).toHaveLength(1);
  });
});

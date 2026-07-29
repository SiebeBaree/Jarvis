import { describe, expect, it } from "vitest";
import {
  goalCreateSchema,
  goalPatchSchema,
  habitLogSchema,
  isValidTimezone,
  metricEntriesQuerySchema,
  settingsPatchSchema,
  taskCreateSchema,
} from "../src/lib/validation";

const UUID = "6f1b3c2e-9d4a-4f5b-8c1d-2e3f4a5b6c7d";

describe("settings timezone validation", () => {
  it("accepts a valid IANA timezone", () => {
    expect(isValidTimezone("Europe/Brussels")).toBe(true);
    expect(settingsPatchSchema.safeParse({ timezone: "Europe/Brussels" }).success).toBe(true);
  });

  it("rejects a misspelled timezone", () => {
    expect(isValidTimezone("Europe/Brussel")).toBe(false);
    expect(settingsPatchSchema.safeParse({ timezone: "Europe/Brussel" }).success).toBe(false);
  });

  it("rejects a non-IANA offset string", () => {
    expect(isValidTimezone("CET+1")).toBe(false);
    expect(settingsPatchSchema.safeParse({ timezone: "CET+1" }).success).toBe(false);
  });
});

describe("metric entries query", () => {
  it("allows omitting typeId (Body screen loads all types at once)", () => {
    expect(metricEntriesQuerySchema.safeParse({}).success).toBe(true);
    expect(
      metricEntriesQuerySchema.safeParse({ from: "2026-07-01", to: "2026-07-21" }).success,
    ).toBe(true);
  });

  it("still rejects a malformed typeId", () => {
    expect(metricEntriesQuerySchema.safeParse({ typeId: "not-a-uuid" }).success).toBe(false);
  });
});

describe("client-supplied ids for idempotent writes", () => {
  it("accepts a task create with or without an id", () => {
    expect(taskCreateSchema.safeParse({ title: "Ship it" }).success).toBe(true);
    const parsed = taskCreateSchema.safeParse({ title: "Ship it", id: UUID });
    expect(parsed.success && parsed.data.id).toBe(UUID);
  });

  it("rejects a task id that is not a uuid", () => {
    expect(taskCreateSchema.safeParse({ title: "Ship it", id: "42" }).success).toBe(false);
  });

  it("accepts a habit log with or without a completionId", () => {
    expect(habitLogSchema.safeParse({}).success).toBe(true);
    const parsed = habitLogSchema.safeParse({ dayKey: "2026-07-25", completionId: UUID });
    expect(parsed.success && parsed.data.completionId).toBe(UUID);
  });

  it("rejects a completionId that is not a uuid", () => {
    expect(habitLogSchema.safeParse({ completionId: "nope" }).success).toBe(false);
  });
});

describe("goal schemas", () => {
  const base = { title: "Reach 10k MRR", targetDate: "2026-12-31" };

  it("accepts an untracked goal (dates only)", () => {
    expect(goalCreateSchema.safeParse(base).success).toBe(true);
  });

  it("accepts a full numeric goal", () => {
    const parsed = goalCreateSchema.safeParse({
      ...base,
      horizon: "long",
      unit: "EUR",
      startValue: 0,
      targetValue: 10_000,
      currentValue: 3400,
    });
    expect(parsed.success).toBe(true);
  });

  it("rejects a half-configured numeric target", () => {
    expect(goalCreateSchema.safeParse({ ...base, targetValue: 10 }).success).toBe(false);
    expect(goalCreateSchema.safeParse({ ...base, startValue: 10 }).success).toBe(false);
  });

  it("rejects a target equal to the baseline (no progress to measure)", () => {
    expect(
      goalCreateSchema.safeParse({ ...base, startValue: 80, targetValue: 80 }).success,
    ).toBe(false);
  });

  it("rejects a targetDate before the startDate", () => {
    expect(
      goalCreateSchema.safeParse({ ...base, startDate: "2027-01-01" }).success,
    ).toBe(false);
  });

  it("patch accepts an empty object and rejects unknown keys", () => {
    expect(goalPatchSchema.safeParse({}).success).toBe(true);
    expect(goalPatchSchema.safeParse({ status: "achieved" }).success).toBe(true);
    expect(goalPatchSchema.safeParse({ blockId: UUID }).success).toBe(false);
  });
});

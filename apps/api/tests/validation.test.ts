import { describe, expect, it } from "vitest";
import {
  blockPatchSchema,
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

describe("block patch", () => {
  it("accepts title and startDate independently", () => {
    expect(blockPatchSchema.safeParse({}).success).toBe(true);
    expect(blockPatchSchema.safeParse({ title: "Q3" }).success).toBe(true);
    expect(blockPatchSchema.safeParse({ startDate: "2026-07-06" }).success).toBe(true);
    expect(blockPatchSchema.safeParse({ title: "Q3", startDate: "2026-07-06" }).success).toBe(true);
  });

  it("rejects a malformed startDate", () => {
    expect(blockPatchSchema.safeParse({ startDate: "2026-13-01" }).success).toBe(false);
  });

  it("still rejects unknown keys, endDate included (it follows from startDate)", () => {
    expect(blockPatchSchema.safeParse({ endDate: "2026-10-04" }).success).toBe(false);
  });
});

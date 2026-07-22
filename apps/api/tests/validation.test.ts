import { describe, expect, it } from "vitest";
import {
  isValidTimezone,
  metricEntriesQuerySchema,
  settingsPatchSchema,
} from "../src/lib/validation";

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

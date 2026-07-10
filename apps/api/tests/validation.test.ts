import { describe, expect, it } from "vitest";
import { isValidTimezone, settingsPatchSchema } from "../src/lib/validation";

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

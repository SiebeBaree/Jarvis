import { describe, expect, it } from "vitest";
import { addDays, isoWeekday, localDateString } from "../dates";

describe("localDateString", () => {
  it("returns the same calendar date after the boundary in Europe/Brussels", () => {
    // 2026-07-07 10:00 local (Brussels is UTC+2 in July) -> 08:00 UTC
    const now = new Date("2026-07-07T08:00:00Z");
    expect(localDateString(now, "Europe/Brussels")).toBe("2026-07-07");
  });

  it("rolls back to the previous day before 03:00 in Europe/Brussels", () => {
    // 2026-07-07 01:30 local -> 2026-07-06T23:30Z
    const now = new Date("2026-07-06T23:30:00Z");
    expect(localDateString(now, "Europe/Brussels")).toBe("2026-07-06");
  });

  it("treats exactly the boundary (03:00) as the new day", () => {
    // 2026-07-07 03:00 local -> 2026-07-07T01:00Z
    const now = new Date("2026-07-07T01:00:00Z");
    expect(localDateString(now, "Europe/Brussels")).toBe("2026-07-07");
  });

  it("respects a custom boundary", () => {
    // 2026-07-07 05:30 local, boundary 06:00 -> still previous day
    const now = new Date("2026-07-07T03:30:00Z");
    expect(localDateString(now, "Europe/Brussels", "06:00")).toBe("2026-07-06");
    // same instant, boundary 05:00 -> new day
    expect(localDateString(now, "Europe/Brussels", "05:00")).toBe("2026-07-07");
  });

  it("handles UTC vs local mismatch around midnight (timezone ahead of UTC)", () => {
    // 2026-07-06T22:30Z is 2026-07-07 07:30 in Asia/Tokyo (UTC+9)
    const now = new Date("2026-07-06T22:30:00Z");
    expect(localDateString(now, "Asia/Tokyo")).toBe("2026-07-07");
    expect(localDateString(now, "UTC")).toBe("2026-07-06");
  });

  it("handles a timezone behind UTC crossing midnight", () => {
    // 2026-07-07T02:00Z is 2026-07-06 22:00 in America/New_York (UTC-4 in July)
    const now = new Date("2026-07-07T02:00:00Z");
    expect(localDateString(now, "America/New_York")).toBe("2026-07-06");
  });

  it("handles a DST spring-forward date (Europe/Brussels, 2026-03-29)", () => {
    // DST begins 2026-03-29 in Brussels: clocks jump 02:00 -> 03:00 (UTC+1 -> UTC+2).
    // 2026-03-29T02:30Z = 04:30 local (after the jump, UTC+2) -> new day, past 03:00.
    const now = new Date("2026-03-29T02:30:00Z");
    expect(localDateString(now, "Europe/Brussels")).toBe("2026-03-29");
    // 2026-03-29T00:30Z = 01:30 local (before jump, UTC+1) -> before 03:00 -> previous day.
    const early = new Date("2026-03-29T00:30:00Z");
    expect(localDateString(early, "Europe/Brussels")).toBe("2026-03-28");
  });
});

describe("isoWeekday", () => {
  it("computes 1=Mon .. 7=Sun", () => {
    expect(isoWeekday("2026-07-06")).toBe(1); // Monday
    expect(isoWeekday("2026-07-07")).toBe(2); // Tuesday
    expect(isoWeekday("2026-07-11")).toBe(6); // Saturday
    expect(isoWeekday("2026-07-12")).toBe(7); // Sunday
  });
});

describe("addDays", () => {
  it("adds and subtracts days across month boundaries", () => {
    expect(addDays("2026-07-06", 1)).toBe("2026-07-07");
    expect(addDays("2026-07-06", -1)).toBe("2026-07-05");
    expect(addDays("2026-07-31", 1)).toBe("2026-08-01");
    expect(addDays("2026-01-01", -1)).toBe("2025-12-31");
  });

  it("adds days across a leap-year February", () => {
    expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
    expect(addDays("2028-02-29", 1)).toBe("2028-03-01");
  });
});

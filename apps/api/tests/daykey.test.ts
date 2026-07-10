import { describe, expect, it } from "vitest";
import {
  addDays,
  dayKeyFor,
  diffDays,
  elapsedDayOfWeek,
  isReviewWeek,
  isValidDayKey,
  isoWeekday,
  weekEnd,
  weekIndexInBlock,
  weekStart,
} from "../src/lib/daykey";

const TZ = "Europe/Brussels";

describe("dayKeyFor (3 AM boundary)", () => {
  it("assigns 02:30 local to the previous day", () => {
    // 2026-07-10 02:30 CEST (+02:00)
    expect(dayKeyFor(new Date("2026-07-10T02:30:00+02:00"), TZ, 3)).toBe("2026-07-09");
  });

  it("assigns 03:00 local to the same day", () => {
    expect(dayKeyFor(new Date("2026-07-10T03:00:00+02:00"), TZ, 3)).toBe("2026-07-10");
  });

  it("assigns midday to the same day", () => {
    expect(dayKeyFor(new Date("2026-07-10T14:00:00+02:00"), TZ, 3)).toBe("2026-07-10");
  });

  it("handles midnight sharp as previous day", () => {
    expect(dayKeyFor(new Date("2026-07-11T00:00:00+02:00"), TZ, 3)).toBe("2026-07-10");
  });

  it("respects a different boundary hour", () => {
    expect(dayKeyFor(new Date("2026-07-10T02:30:00+02:00"), TZ, 0)).toBe("2026-07-10");
  });

  it("works across the spring-forward DST transition (2026-03-29)", () => {
    // 01:30 CET (before the jump) → still shifted into the previous day
    expect(dayKeyFor(new Date("2026-03-29T00:30:00Z"), TZ, 3)).toBe("2026-03-28");
    // 04:00 CEST (after the jump, past the boundary) → same day
    expect(dayKeyFor(new Date("2026-03-29T02:00:00Z"), TZ, 3)).toBe("2026-03-29");
  });

  it("works across the fall-back DST transition (2026-10-25)", () => {
    // 02:30 CEST first pass (00:30Z) → previous day
    expect(dayKeyFor(new Date("2026-10-25T00:30:00Z"), TZ, 3)).toBe("2026-10-24");
    // 03:30 CET after the fall-back (02:30Z) → same day
    expect(dayKeyFor(new Date("2026-10-25T02:30:00Z"), TZ, 3)).toBe("2026-10-25");
  });

  it("handles UTC-negative timezones", () => {
    expect(dayKeyFor(new Date("2026-07-10T01:00:00-04:00"), "America/New_York", 3)).toBe(
      "2026-07-09",
    );
  });
});

describe("calendar arithmetic", () => {
  it("validates dayKeys", () => {
    expect(isValidDayKey("2026-07-10")).toBe(true);
    expect(isValidDayKey("2026-02-30")).toBe(false);
    expect(isValidDayKey("2026-7-1")).toBe(false);
    expect(isValidDayKey("garbage")).toBe(false);
  });

  it("adds and diffs days across month boundaries", () => {
    expect(addDays("2026-07-31", 1)).toBe("2026-08-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28"); // 2026 not a leap year
    expect(diffDays("2026-07-01", "2026-07-10")).toBe(9);
    expect(diffDays("2026-07-10", "2026-07-01")).toBe(-9);
  });

  it("computes ISO weekdays and week bounds (Monday start)", () => {
    expect(isoWeekday("2026-07-10")).toBe(5); // Friday
    expect(isoWeekday("2026-07-12")).toBe(7); // Sunday
    expect(isoWeekday("2026-07-06")).toBe(1); // Monday
    expect(weekStart("2026-07-10")).toBe("2026-07-06");
    expect(weekStart("2026-07-06")).toBe("2026-07-06");
    expect(weekEnd("2026-07-10")).toBe("2026-07-12");
    expect(elapsedDayOfWeek("2026-07-08")).toBe(3); // Wednesday
  });
});

describe("block weeks", () => {
  const blockStart = "2026-07-06"; // a Monday
  const blockEnd = addDays(blockStart, 13 * 7 - 1); // 2026-10-04, Sunday of week 13

  it("computes week index within a block", () => {
    expect(weekIndexInBlock("2026-07-06", blockStart)).toBe(1);
    expect(weekIndexInBlock("2026-07-12", blockStart)).toBe(1);
    expect(weekIndexInBlock("2026-07-13", blockStart)).toBe(2);
    expect(weekIndexInBlock(blockEnd, blockStart)).toBe(13);
  });

  it("flags week 13 as review week, inside the block only", () => {
    expect(isReviewWeek(addDays(blockStart, 12 * 7), blockStart, blockEnd)).toBe(true);
    expect(isReviewWeek(blockEnd, blockStart, blockEnd)).toBe(true);
    expect(isReviewWeek(addDays(blockStart, 11 * 7), blockStart, blockEnd)).toBe(false);
    expect(isReviewWeek(addDays(blockEnd, 1), blockStart, blockEnd)).toBe(false);
    expect(isReviewWeek(addDays(blockStart, -1), blockStart, blockEnd)).toBe(false);
  });
});

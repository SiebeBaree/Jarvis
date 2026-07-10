import { describe, expect, it } from "vitest";
import { nextOccurrence, occurrencesToGenerate } from "../src/lib/recurrence";

describe("occurrencesToGenerate", () => {
  it("daily every 1: generates each day from startDate, once", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "daily", interval: 1 },
      startDate: "2026-07-08",
      endDate: null,
      lastGeneratedThrough: null,
      through: "2026-07-10",
    });
    expect(days).toEqual(["2026-07-08", "2026-07-09", "2026-07-10"]);
  });

  it("daily: the high-water mark prevents regeneration", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "daily", interval: 1 },
      startDate: "2026-07-01",
      endDate: null,
      lastGeneratedThrough: "2026-07-08",
      through: "2026-07-10",
    });
    expect(days).toEqual(["2026-07-09", "2026-07-10"]);
  });

  it("daily every 3: keeps the phase anchored to startDate", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "daily", interval: 3 },
      startDate: "2026-07-01",
      endDate: null,
      lastGeneratedThrough: "2026-07-02",
      through: "2026-07-14",
    });
    expect(days).toEqual(["2026-07-04", "2026-07-07", "2026-07-10", "2026-07-13"]);
  });

  it("weekly on Mon+Thu: emits both days each week", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "weekly", interval: 1, byWeekday: [1, 4] },
      startDate: "2026-07-06", // Monday
      endDate: null,
      lastGeneratedThrough: null,
      through: "2026-07-19",
    });
    expect(days).toEqual(["2026-07-06", "2026-07-09", "2026-07-13", "2026-07-16"]);
  });

  it("weekly interval 2: skips alternate weeks, anchored to the start week", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "weekly", interval: 2, byWeekday: [3] }, // Wednesdays
      startDate: "2026-07-06",
      endDate: null,
      lastGeneratedThrough: null,
      through: "2026-08-02",
    });
    expect(days).toEqual(["2026-07-08", "2026-07-22"]);
  });

  it("weekly: does not emit occurrences before startDate mid-week", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "weekly", interval: 1, byWeekday: [1, 5] },
      startDate: "2026-07-08", // Wednesday — Monday 07-06 must not appear
      endDate: null,
      lastGeneratedThrough: null,
      through: "2026-07-13",
    });
    expect(days).toEqual(["2026-07-10", "2026-07-13"]);
  });

  it("monthly day 31: clamps to short months", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "monthly", interval: 1, byMonthDay: 31 },
      startDate: "2026-01-31",
      endDate: null,
      lastGeneratedThrough: null,
      through: "2026-04-30",
    });
    expect(days).toEqual(["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]);
  });

  it("respects endDate", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "daily", interval: 1 },
      startDate: "2026-07-01",
      endDate: "2026-07-03",
      lastGeneratedThrough: null,
      through: "2026-07-10",
    });
    expect(days).toEqual(["2026-07-01", "2026-07-02", "2026-07-03"]);
  });

  it("returns nothing when already generated through the horizon", () => {
    const days = occurrencesToGenerate({
      rule: { freq: "daily", interval: 1 },
      startDate: "2026-07-01",
      endDate: null,
      lastGeneratedThrough: "2026-07-10",
      through: "2026-07-10",
    });
    expect(days).toEqual([]);
  });
});

describe("nextOccurrence", () => {
  it("finds the next monthly occurrence", () => {
    expect(
      nextOccurrence({ freq: "monthly", interval: 1, byMonthDay: 1 }, "2026-01-01", null, "2026-07-10"),
    ).toBe("2026-08-01");
  });

  it("returns null after endDate", () => {
    expect(
      nextOccurrence({ freq: "daily", interval: 1 }, "2026-07-01", "2026-07-05", "2026-07-05"),
    ).toBeNull();
  });
});

import { describe, expect, it } from "vitest";
import {
  allVariantsForLint,
  composeCheckinNudge,
  type CheckinNudgeData,
} from "../src/lib/notifications/message";

const base: CheckinNudgeData = {
  dayKey: "2026-08-18",
  yesterdayMood: 55,
  openTasksToday: 0,
  overdueTasks: 0,
  bestActiveStreak: null,
  hasAnyMoodEntry: true,
};

const category = (patch: Partial<CheckinNudgeData>) =>
  composeCheckinNudge({ ...base, ...patch }).category;

describe("nudge category ladder", () => {
  it("puts a never-used account first, whatever else is true", () => {
    expect(
      category({ hasAnyMoodEntry: false, yesterdayMood: 10, overdueTasks: 9 }),
    ).toBe("first_entry");
  });

  it("treats mood at or below 40 as a bad day", () => {
    expect(category({ yesterdayMood: 40 })).toBe("yesterday_bad");
    expect(category({ yesterdayMood: 41 })).not.toBe("yesterday_bad");
  });

  it("mentions overdue tasks from the first one", () => {
    expect(category({ overdueTasks: 1 })).toBe("overdue");
    expect(category({ overdueTasks: 0 })).not.toBe("overdue");
  });

  it("mentions a streak from three days", () => {
    expect(category({ bestActiveStreak: { habitName: "Gym", days: 3 } })).toBe("streak");
    expect(category({ bestActiveStreak: { habitName: "Gym", days: 2 } })).not.toBe("streak");
  });

  it("calls a day busy from four open tasks", () => {
    expect(category({ openTasksToday: 4 })).toBe("busy_day");
    expect(category({ openTasksToday: 3 })).not.toBe("busy_day");
  });

  it("treats mood at or above 70 as a good day", () => {
    expect(category({ yesterdayMood: 70 })).toBe("yesterday_good");
    expect(category({ yesterdayMood: 69 })).toBe("generic");
  });

  it("falls back to generic when nothing stands out", () => {
    expect(category({})).toBe("generic");
    expect(category({ yesterdayMood: null })).toBe("generic");
  });

  it("prefers a bad day over overdue tasks and streaks", () => {
    expect(
      category({ yesterdayMood: 20, overdueTasks: 5, bestActiveStreak: { habitName: "Gym", days: 9 } }),
    ).toBe("yesterday_bad");
  });
});

describe("nudge text", () => {
  it("returns the same message for the same day, so a retry cannot differ", () => {
    const first = composeCheckinNudge(base);
    const second = composeCheckinNudge({ ...base });
    expect(second).toEqual(first);
  });

  it("rotates variants across days", () => {
    const bodies = new Set(
      ["2026-08-18", "2026-08-19", "2026-08-20", "2026-08-21", "2026-08-22", "2026-08-23"].map(
        (dayKey) => composeCheckinNudge({ ...base, dayKey }).body,
      ),
    );
    expect(bodies.size).toBeGreaterThan(1);
  });

  it("interpolates the counts and the habit name it talks about", () => {
    const overdue = composeCheckinNudge({ ...base, overdueTasks: 3 });
    expect(overdue.body).toContain("3");
    const streak = composeCheckinNudge({
      ...base,
      bestActiveStreak: { habitName: "Morning run", days: 12 },
    });
    expect(streak.body).toContain("Morning run");
    expect(streak.body).toContain("12");
  });

  it("reads correctly for a single task", () => {
    const one = composeCheckinNudge({ ...base, overdueTasks: 1 });
    expect(one.body).not.toMatch(/1 tasks are/);
  });

  it("records which template fired", () => {
    expect(composeCheckinNudge({ ...base, overdueTasks: 2 }).template).toMatch(/^overdue:\d+$/);
  });
});

describe("persona rules", () => {
  const variants = allVariantsForLint();

  it("covers every catalogue entry", () => {
    expect(variants.length).toBeGreaterThan(20);
  });

  it("never shouts", () => {
    for (const { body, title } of variants) {
      expect(`${title} ${body}`).not.toContain("!");
    }
  });

  it("never uses a dash glyph", () => {
    for (const { body, title } of variants) {
      expect(`${title} ${body}`).not.toMatch(/[–—]/);
    }
  });

  it("stays short enough for a lock screen", () => {
    for (const { body, title } of variants) {
      expect(title.length).toBeGreaterThan(0);
      expect(body.length).toBeGreaterThan(0);
      expect(body.length).toBeLessThan(160);
    }
  });

  it("leaves no unfilled placeholder", () => {
    for (const { body } of variants) {
      expect(body).not.toContain("undefined");
      expect(body).not.toMatch(/[[\]{}]/);
    }
  });
});

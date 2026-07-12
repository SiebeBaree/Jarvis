import { describe, expect, it } from "vitest";
import { buildAreaDTO, weekKeyFor, type AreaLike, type CheckinLike } from "../src/lib/checkins";
import {
  improvementAreaCreateSchema,
  improvementAreaPatchSchema,
} from "../src/lib/validation";

describe("weekKeyFor", () => {
  it("maps any weekday to that week's Monday", () => {
    expect(weekKeyFor("2026-07-06")).toBe("2026-07-06"); // Monday
    expect(weekKeyFor("2026-07-08")).toBe("2026-07-06"); // Wednesday
    expect(weekKeyFor("2026-07-12")).toBe("2026-07-06"); // Sunday
    expect(weekKeyFor("2026-07-13")).toBe("2026-07-13"); // next Monday
  });

  it("handles year boundaries", () => {
    // 2026-01-01 is a Thursday; its ISO week starts Monday 2025-12-29.
    expect(weekKeyFor("2026-01-01")).toBe("2025-12-29");
  });
});

const area = (over: Partial<AreaLike> = {}): AreaLike => ({
  id: "area-1",
  name: "Posture",
  emoji: "🧍",
  betterLooksLike: "Straight back at the desk",
  sortOrder: 0,
  archivedAt: null,
  ...over,
});

const checkin = (over: Partial<CheckinLike> = {}): CheckinLike => ({
  id: "chk-1",
  weekKey: "2026-07-06",
  dayKey: "2026-07-08",
  aiCommentary: "Shoulders less rounded than last week.",
  createdAt: new Date("2026-07-08T10:00:00Z"),
  ...over,
});

describe("buildAreaDTO due logic", () => {
  const currentWeek = "2026-07-06";

  it("no check-ins → due this week", () => {
    const dto = buildAreaDTO(area(), null, currentWeek);
    expect(dto.dueThisWeek).toBe(true);
    expect(dto.thisWeek).toBeNull();
    expect(dto.lastCheckinAt).toBeNull();
  });

  it("check-in this week → not due, thisWeek populated", () => {
    const dto = buildAreaDTO(area(), checkin(), currentWeek);
    expect(dto.dueThisWeek).toBe(false);
    expect(dto.thisWeek).toEqual({ id: "chk-1", dayKey: "2026-07-08", hasCommentary: true });
  });

  it("check-in from a previous week → due again", () => {
    const dto = buildAreaDTO(area(), checkin({ weekKey: "2026-06-29", dayKey: "2026-07-01" }), currentWeek);
    expect(dto.dueThisWeek).toBe(true);
    expect(dto.thisWeek).toBeNull();
    expect(dto.lastCheckinAt).toBe("2026-07-01");
  });

  it("pending commentary is reported", () => {
    const dto = buildAreaDTO(area(), checkin({ aiCommentary: null }), currentWeek);
    expect(dto.thisWeek?.hasCommentary).toBe(false);
  });

  it("archived areas are never due", () => {
    const dto = buildAreaDTO(area({ archivedAt: new Date() }), null, currentWeek);
    expect(dto.archived).toBe(true);
    expect(dto.dueThisWeek).toBe(false);
  });
});

describe("improvement area schemas", () => {
  it("create requires a name", () => {
    expect(improvementAreaCreateSchema.safeParse({ name: "Teeth" }).success).toBe(true);
    expect(improvementAreaCreateSchema.safeParse({}).success).toBe(false);
  });

  it("patch is strict and supports archive + explicit nulls", () => {
    expect(improvementAreaPatchSchema.safeParse({ archived: true }).success).toBe(true);
    expect(improvementAreaPatchSchema.safeParse({ betterLooksLike: null }).success).toBe(true);
    expect(improvementAreaPatchSchema.safeParse({ bogus: 1 }).success).toBe(false);
  });
});

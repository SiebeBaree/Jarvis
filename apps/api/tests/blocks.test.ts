import { describe, expect, it } from "vitest";

// blocks.ts imports the db client, which throws without DATABASE_URL. The pure
// helper under test never touches the database, so a placeholder is enough.
process.env.DATABASE_URL ??= "postgresql://unit:test@localhost:5432/unit_test";

const { assertNoBlockOverlap, blockStatusForRange, blockStatusTransitions } = await import(
  "../src/lib/blocks"
);

type Input = Parameters<typeof blockStatusTransitions>[0][number];

function block(overrides: Partial<Input> & Pick<Input, "id" | "status" | "startDate" | "endDate">): Input {
  return overrides;
}

describe("blockStatusTransitions", () => {
  it("completes an active block whose endDate is in the past", () => {
    const transitions = blockStatusTransitions(
      [block({ id: "a", status: "active", startDate: "2026-01-05", endDate: "2026-04-05" })],
      "2026-04-06",
    );
    expect(transitions.get("a")).toBe("completed");
    expect(transitions.size).toBe(1);
  });

  it("activates a planned block covering today when no active block does", () => {
    const transitions = blockStatusTransitions(
      [block({ id: "p", status: "planned", startDate: "2026-07-06", endDate: "2026-10-04" })],
      "2026-07-10",
    );
    expect(transitions.get("p")).toBe("active");
    expect(transitions.size).toBe(1);
  });

  it("leaves a planned block in the future unchanged", () => {
    const transitions = blockStatusTransitions(
      [block({ id: "p", status: "planned", startDate: "2026-08-03", endDate: "2026-11-01" })],
      "2026-07-10",
    );
    expect(transitions.size).toBe(0);
  });

  it("applies both transitions in one pass (ended active + planned start arrived)", () => {
    const transitions = blockStatusTransitions(
      [
        block({ id: "old", status: "active", startDate: "2026-01-05", endDate: "2026-04-05" }),
        block({ id: "next", status: "planned", startDate: "2026-07-06", endDate: "2026-10-04" }),
        block({ id: "done", status: "completed", startDate: "2025-10-06", endDate: "2026-01-04" }),
      ],
      "2026-07-10",
    );
    expect(transitions.get("old")).toBe("completed");
    expect(transitions.get("next")).toBe("active");
    expect(transitions.size).toBe(2);
  });

  it("does nothing when an active block already covers today", () => {
    const transitions = blockStatusTransitions(
      [
        block({ id: "a", status: "active", startDate: "2026-07-06", endDate: "2026-10-04" }),
        block({ id: "p", status: "planned", startDate: "2026-10-05", endDate: "2027-01-03" }),
      ],
      "2026-07-10",
    );
    expect(transitions.size).toBe(0);
  });
});

type RangeInput = Parameters<typeof assertNoBlockOverlap>[0][number];

const existing: RangeInput[] = [
  { id: "a", title: "Block 1", startDate: "2026-04-06", endDate: "2026-07-05" },
  { id: "b", title: "Block 2", startDate: "2026-07-06", endDate: "2026-10-04" },
];

describe("assertNoBlockOverlap", () => {
  it("accepts a range that sits in the gap after the last block", () => {
    expect(() => assertNoBlockOverlap(existing, "2026-10-05", "2027-01-03")).not.toThrow();
  });

  it("rejects a range overlapping another block, naming it", () => {
    expect(() => assertNoBlockOverlap(existing, "2026-06-01", "2026-08-30")).toThrowError(
      /Overlaps existing block "Block 1"/,
    );
  });

  it("rejects a touching edge (ranges are inclusive)", () => {
    expect(() => assertNoBlockOverlap(existing, "2026-10-04", "2027-01-02")).toThrowError(
      /Block 2/,
    );
  });

  it("ignores the block being moved, which always overlaps itself", () => {
    expect(() => assertNoBlockOverlap(existing, "2026-07-06", "2026-10-04", "b")).not.toThrow();
  });

  it("still rejects when a moved block lands on a different block", () => {
    expect(() => assertNoBlockOverlap(existing, "2026-05-04", "2026-08-02", "b")).toThrowError(
      /Block 1/,
    );
  });
});

describe("blockStatusForRange", () => {
  it("activates a range covering today when no other block is active", () => {
    expect(
      blockStatusForRange({ startDate: "2026-07-06", endDate: "2026-10-04" }, "2026-07-10", false),
    ).toBe("active");
  });

  it("plans a range covering today when another block holds the active slot", () => {
    expect(
      blockStatusForRange({ startDate: "2026-07-06", endDate: "2026-10-04" }, "2026-07-10", true),
    ).toBe("planned");
  });

  it("plans a range moved entirely into the future", () => {
    expect(
      blockStatusForRange({ startDate: "2026-08-03", endDate: "2026-11-01" }, "2026-07-10", false),
    ).toBe("planned");
  });

  it("completes a range moved entirely into the past", () => {
    expect(
      blockStatusForRange({ startDate: "2026-01-05", endDate: "2026-04-05" }, "2026-07-10", false),
    ).toBe("completed");
  });

  it("treats the boundary days as covering today", () => {
    const range = { startDate: "2026-07-06", endDate: "2026-10-04" };
    expect(blockStatusForRange(range, "2026-07-06", false)).toBe("active");
    expect(blockStatusForRange(range, "2026-10-04", false)).toBe("active");
    expect(blockStatusForRange(range, "2026-10-05", false)).toBe("completed");
  });
});

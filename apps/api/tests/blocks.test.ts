import { describe, expect, it } from "vitest";

// blocks.ts imports the db client, which throws without DATABASE_URL. The pure
// helper under test never touches the database, so a placeholder is enough.
process.env.DATABASE_URL ??= "postgresql://unit:test@localhost:5432/unit_test";

const { blockStatusTransitions } = await import("../src/lib/blocks");

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

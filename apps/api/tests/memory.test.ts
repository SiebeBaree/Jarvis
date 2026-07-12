import { describe, expect, it } from "vitest";
import { applyMemoryOps, memoryOpsSchema, type MemoryOp } from "../src/lib/ai/memory-ops";
import { memoryCreateSchema, memoryPatchSchema } from "../src/lib/validation";

const existing = new Set(["mem-1", "mem-2"]);

describe("applyMemoryOps", () => {
  it("resolves valid add/update/delete ops", () => {
    const ops: MemoryOp[] = [
      { op: "add", id: null, category: "work", content: "He is the technical co-founder." },
      { op: "update", id: "mem-1", category: null, content: "He works from home most days." },
      { op: "delete", id: "mem-2", category: null, content: null },
    ];
    const resolved = applyMemoryOps(ops, existing);
    expect(resolved.adds).toEqual([{ category: "work", content: "He is the technical co-founder." }]);
    expect(resolved.updates).toEqual([
      { id: "mem-1", category: null, content: "He works from home most days." },
    ]);
    expect(resolved.deletes).toEqual(["mem-2"]);
  });

  it("drops updates/deletes for ids that do not belong to the user", () => {
    const ops: MemoryOp[] = [
      { op: "update", id: "other-users-id", category: null, content: "hijack" },
      { op: "delete", id: "nope", category: null, content: null },
    ];
    const resolved = applyMemoryOps(ops, existing);
    expect(resolved.updates).toEqual([]);
    expect(resolved.deletes).toEqual([]);
  });

  it("drops adds without category or content, and blank content", () => {
    const ops: MemoryOp[] = [
      { op: "add", id: null, category: null, content: "no category" },
      { op: "add", id: null, category: "health", content: "   " },
      { op: "update", id: "mem-1", category: null, content: null },
    ];
    const resolved = applyMemoryOps(ops, existing);
    expect(resolved.adds).toEqual([]);
    expect(resolved.updates).toEqual([]);
  });

  it("caps at 8 ops per turn", () => {
    const ops: MemoryOp[] = Array.from({ length: 12 }, (_, i) => ({
      op: "add" as const,
      id: null,
      category: "context" as const,
      content: `fact ${i}`,
    }));
    const resolved = applyMemoryOps(ops, existing);
    expect(resolved.adds).toHaveLength(8);
  });

  it("truncates content to 500 chars", () => {
    const ops: MemoryOp[] = [
      { op: "add", id: null, category: "context", content: "x".repeat(600) },
    ];
    const resolved = applyMemoryOps(ops, existing);
    expect(resolved.adds[0]!.content).toHaveLength(500);
  });
});

describe("memory schemas", () => {
  it("accepts a valid extraction payload", () => {
    const parsed = memoryOpsSchema.safeParse({
      ops: [{ op: "add", id: null, category: "appearance", content: "He wants better posture." }],
    });
    expect(parsed.success).toBe(true);
  });

  it("rejects unknown categories", () => {
    expect(memoryCreateSchema.safeParse({ category: "astrology", content: "x" }).success).toBe(false);
    expect(memoryCreateSchema.safeParse({ category: "appearance", content: "x" }).success).toBe(true);
  });

  it("patch is strict and partial", () => {
    expect(memoryPatchSchema.safeParse({}).success).toBe(true);
    expect(memoryPatchSchema.safeParse({ content: "new" }).success).toBe(true);
    expect(memoryPatchSchema.safeParse({ nope: 1 }).success).toBe(false);
  });
});

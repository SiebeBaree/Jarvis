// Pure memory-extraction op logic — no db imports so unit tests can load it
// without DATABASE_URL. Persistence lives in memory.ts.

import { z } from "zod";
import { memoryCategories } from "../validation";

export const MAX_OPS_PER_TURN = 8;

export const memoryOpSchema = z.strictObject({
  op: z.enum(["add", "update", "delete"]),
  id: z.string().nullable(), // existing memory id for update/delete; null for add
  category: z.enum(memoryCategories).nullable(), // required for add
  content: z.string().nullable(), // required for add/update
});
export const memoryOpsSchema = z.strictObject({ ops: z.array(memoryOpSchema) });
export type MemoryOp = z.infer<typeof memoryOpSchema>;

export interface ResolvedOps {
  adds: { category: string; content: string }[];
  updates: { id: string; category: string | null; content: string }[];
  deletes: string[];
}

/**
 * Validates model-proposed ops against the user's existing memories. Pure —
 * unknown ids, missing fields, and anything past the per-turn cap are dropped
 * rather than erroring (extraction is best-effort by design).
 */
export function applyMemoryOps(ops: MemoryOp[], existingIds: Set<string>): ResolvedOps {
  const resolved: ResolvedOps = { adds: [], updates: [], deletes: [] };
  for (const op of ops.slice(0, MAX_OPS_PER_TURN)) {
    const content = op.content?.trim().slice(0, 500) ?? "";
    switch (op.op) {
      case "add":
        if (op.category && content) resolved.adds.push({ category: op.category, content });
        break;
      case "update":
        if (op.id && existingIds.has(op.id) && content) {
          resolved.updates.push({ id: op.id, category: op.category, content });
        }
        break;
      case "delete":
        if (op.id && existingIds.has(op.id)) resolved.deletes.push(op.id);
        break;
    }
  }
  return resolved;
}

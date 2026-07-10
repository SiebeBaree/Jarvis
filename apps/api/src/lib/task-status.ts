// Shared logic for POST /tasks/:id/complete and /tasks/:id/uncomplete.

import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { tasks } from "@/db/schema";
import type { AuthContext } from "./auth";
import { ApiError } from "./http";
import { recomputeDay, todayKey } from "./scoring/snapshot";
import { withSubtasks, type TaskDTO } from "./today";

/**
 * Mark a task done/open and recompute the affected day's score.
 * - Completing late retro-credits the task's original due date.
 * - Subtasks affect their PARENT's due-date day (that's where credit lives).
 * - No due date anywhere → recompute today so the live score updates.
 */
export async function setTaskCompletion(
  ctx: AuthContext,
  taskId: string,
  done: boolean,
): Promise<TaskDTO> {
  const task = await db.query.tasks.findFirst({
    where: and(eq(tasks.id, taskId), eq(tasks.userId, ctx.userId)),
  });
  if (!task) throw new ApiError(404, "not_found", "Task not found");

  // No-op when already in the requested state.
  if ((task.status === "done") === done) {
    const [dto] = await withSubtasks([task]);
    return dto as TaskDTO;
  }

  const [updated] = await db
    .update(tasks)
    .set({
      status: done ? "done" : "open",
      completedAt: done ? new Date() : null,
      updatedAt: new Date(),
    })
    .where(and(eq(tasks.id, taskId), eq(tasks.userId, ctx.userId)))
    .returning();
  if (!updated) throw new ApiError(404, "not_found", "Task not found");

  let recomputeKey: string | null = updated.dueDate;
  if (updated.parentTaskId) {
    const parent = await db.query.tasks.findFirst({
      where: and(eq(tasks.id, updated.parentTaskId), eq(tasks.userId, ctx.userId)),
    });
    recomputeKey = parent?.dueDate ?? null;
  }
  await recomputeDay(ctx.userId, ctx.settings, recomputeKey ?? todayKey(ctx.settings));

  const [dto] = await withSubtasks([updated]);
  return dto as TaskDTO;
}

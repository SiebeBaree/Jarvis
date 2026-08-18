// Full account data reset: wipes every domain row for the authenticated user
// while keeping the account itself (users, sessions, settings). Requires an
// explicit confirm literal so no client bug can trigger it accidentally.

import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import {
  areaCheckins,
  areas,
  dailyScores,
  goalMilestones,
  goals,
  exercises,
  habitCompletions,
  habits,
  improvementAreas,
  mealPrepIngredients,
  mealPreps,
  metricEntries,
  metricTypes,
  moodEntries,
  progressPhotos,
  recurrenceTemplates,
  shoppingItems,
  tasks,
  workoutRoutineExercises,
  workoutRoutines,
  workoutSessions,
  workoutSets,
} from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseBody } from "@/lib/http";
import { accountResetSchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 120; // blob cleanup can take a moment

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  await parseBody(request, accountResetSchema);
  const userId = ctx.userId;

  // Best-effort blob cleanup (photos live outside Postgres).
  const [photos, checkins, meals] = await Promise.all([
    db.query.progressPhotos.findMany({
      where: eq(progressPhotos.userId, userId),
      columns: { blobKey: true },
    }),
    db.query.areaCheckins.findMany({
      where: eq(areaCheckins.userId, userId),
      columns: { blobKey: true },
    }),
    db.query.mealPreps.findMany({
      where: eq(mealPreps.userId, userId),
      columns: { blobKey: true },
    }),
  ]);
  const blobKeys = [...photos, ...checkins, ...meals]
    .map((r) => r.blobKey)
    .filter((key): key is string => key !== null);
  if (blobKeys.length > 0 && process.env.BLOB_READ_WRITE_TOKEN) {
    try {
      const { del } = await import("@vercel/blob");
      await del(blobKeys);
    } catch (error) {
      console.error("Reset blob cleanup failed (ignored):", error);
    }
  }

  // Children first, then parents. Some of this would cascade anyway —
  // explicit order keeps the wipe self-evident and complete.
  await db.delete(areaCheckins).where(eq(areaCheckins.userId, userId));
  await db.delete(improvementAreas).where(eq(improvementAreas.userId, userId));

  await db.delete(habitCompletions).where(eq(habitCompletions.userId, userId));
  await db.delete(habits).where(eq(habits.userId, userId));
  await db.delete(tasks).where(eq(tasks.userId, userId));
  await db.delete(recurrenceTemplates).where(eq(recurrenceTemplates.userId, userId));
  await db.delete(goalMilestones).where(eq(goalMilestones.userId, userId));
  await db.delete(goals).where(eq(goals.userId, userId));
  await db.delete(areas).where(eq(areas.userId, userId));

  await db.delete(moodEntries).where(eq(moodEntries.userId, userId));
  await db.delete(dailyScores).where(eq(dailyScores.userId, userId));
  await db.delete(metricEntries).where(eq(metricEntries.userId, userId));
  await db.delete(metricTypes).where(eq(metricTypes.userId, userId));
  await db.delete(progressPhotos).where(eq(progressPhotos.userId, userId));

  await db.delete(workoutSets).where(eq(workoutSets.userId, userId));
  await db.delete(workoutSessions).where(eq(workoutSessions.userId, userId));
  await db.delete(workoutRoutineExercises).where(eq(workoutRoutineExercises.userId, userId));
  await db.delete(workoutRoutines).where(eq(workoutRoutines.userId, userId));
  await db.delete(exercises).where(eq(exercises.userId, userId));

  await db.delete(mealPrepIngredients).where(eq(mealPrepIngredients.userId, userId));
  await db.delete(mealPreps).where(eq(mealPreps.userId, userId));
  await db.delete(shoppingItems).where(eq(shoppingItems.userId, userId));

  return NextResponse.json({ ok: true });
});

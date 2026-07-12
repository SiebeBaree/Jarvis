// Full account data reset: wipes every domain row for the authenticated user
// while keeping the account itself (users, sessions, settings). Requires an
// explicit confirm literal so no client bug can trigger it accidentally.

import { NextResponse } from "next/server";
import { eq, inArray } from "drizzle-orm";
import { db } from "@/db/client";
import {
  areaCheckins,
  areas,
  blocks,
  briefings,
  conversations,
  dailyScores,
  goals,
  habitCompletions,
  habits,
  improvementAreas,
  interviewSessions,
  memories,
  messages,
  metricEntries,
  metricTypes,
  moodEntries,
  progressPhotos,
  proposedActions,
  recurrenceTemplates,
  tacticCompletions,
  tactics,
  tasks,
  userProfile,
  vision,
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
  const [photos, checkins] = await Promise.all([
    db.query.progressPhotos.findMany({
      where: eq(progressPhotos.userId, userId),
      columns: { blobKey: true },
    }),
    db.query.areaCheckins.findMany({
      where: eq(areaCheckins.userId, userId),
      columns: { blobKey: true },
    }),
  ]);
  const blobKeys = [...photos, ...checkins].map((r) => r.blobKey);
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
  const userTactics = await db.query.tactics.findMany({
    where: eq(tactics.userId, userId),
    columns: { id: true },
  });
  if (userTactics.length > 0) {
    await db.delete(tacticCompletions).where(
      inArray(
        tacticCompletions.tacticId,
        userTactics.map((t) => t.id),
      ),
    );
  }

  await db.delete(proposedActions).where(eq(proposedActions.userId, userId));
  await db.delete(memories).where(eq(memories.userId, userId));
  const userConversations = await db.query.conversations.findMany({
    where: eq(conversations.userId, userId),
    columns: { id: true },
  });
  if (userConversations.length > 0) {
    await db.delete(messages).where(
      inArray(
        messages.conversationId,
        userConversations.map((c) => c.id),
      ),
    );
  }
  await db.delete(conversations).where(eq(conversations.userId, userId));
  await db.delete(briefings).where(eq(briefings.userId, userId));
  await db.delete(interviewSessions).where(eq(interviewSessions.userId, userId));

  await db.delete(areaCheckins).where(eq(areaCheckins.userId, userId));
  await db.delete(improvementAreas).where(eq(improvementAreas.userId, userId));

  await db.delete(habitCompletions).where(eq(habitCompletions.userId, userId));
  await db.delete(habits).where(eq(habits.userId, userId));
  await db.delete(tasks).where(eq(tasks.userId, userId));
  await db.delete(recurrenceTemplates).where(eq(recurrenceTemplates.userId, userId));
  await db.delete(tactics).where(eq(tactics.userId, userId));
  await db.delete(goals).where(eq(goals.userId, userId));
  await db.delete(blocks).where(eq(blocks.userId, userId));
  await db.delete(areas).where(eq(areas.userId, userId));
  await db.delete(vision).where(eq(vision.userId, userId));
  await db.delete(userProfile).where(eq(userProfile.userId, userId));

  await db.delete(moodEntries).where(eq(moodEntries.userId, userId));
  await db.delete(dailyScores).where(eq(dailyScores.userId, userId));
  await db.delete(metricEntries).where(eq(metricEntries.userId, userId));
  await db.delete(metricTypes).where(eq(metricTypes.userId, userId));
  await db.delete(progressPhotos).where(eq(progressPhotos.userId, userId));

  return NextResponse.json({ ok: true });
});

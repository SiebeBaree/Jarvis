// One exercise's progression: a point per session, newest last, so the app can
// draw the line that answers "am I actually getting stronger at this".

import { NextResponse } from "next/server";
import { asc, desc, eq, inArray } from "drizzle-orm";
import { db } from "@/db/client";
import { workoutSessions, workoutSets } from "@/db/schema";
import { requireAuth } from "@/lib/auth";
import { handler, parseQuery } from "@/lib/http";
import { estimateOneRepMax, loadExercise, volumeOf, workingSetCount } from "@/lib/training";
import { exerciseHistoryQuerySchema } from "@/lib/validation";

export const runtime = "nodejs";

export const GET = handler(
  async (request: Request, { params }: { params: Promise<{ id: string }> }) => {
    const ctx = await requireAuth(request);
    const { id } = await params;
    const query = parseQuery(request, exerciseHistoryQuerySchema);

    const exercise = await loadExercise(ctx.userId, id);

    // Newest sessions first for the limit, then reversed so the payload reads
    // left to right as a timeline.
    const sessionRows = await db
      .select({ id: workoutSessions.id, dayKey: workoutSessions.dayKey })
      .from(workoutSessions)
      .innerJoin(workoutSets, eq(workoutSets.sessionId, workoutSessions.id))
      .where(eq(workoutSets.exerciseId, id))
      .groupBy(workoutSessions.id, workoutSessions.dayKey, workoutSessions.startedAt)
      .orderBy(desc(workoutSessions.startedAt))
      .limit(query.limit ?? 60);

    if (sessionRows.length === 0) {
      return NextResponse.json({ exercise, points: [] });
    }

    const setRows = await db
      .select()
      .from(workoutSets)
      .where(
        inArray(
          workoutSets.sessionId,
          sessionRows.map((row) => row.id),
        ),
      )
      .orderBy(asc(workoutSets.setIndex));

    const bySession = new Map<string, typeof setRows>();
    for (const set of setRows) {
      if (set.exerciseId !== id) continue;
      const list = bySession.get(set.sessionId) ?? [];
      list.push(set);
      bySession.set(set.sessionId, list);
    }

    const points = sessionRows
      .slice()
      .reverse()
      .map((session) => {
        const sets = bySession.get(session.id) ?? [];
        const working = sets.filter((set) => !set.isWarmup);
        // "Top set" = the best set by estimated 1RM, which is the honest
        // answer when the heaviest set was also the shortest.
        let top = working[0] ?? null;
        let bestEstimate = top ? estimateOneRepMax(top.weightKg, top.reps) : 0;
        for (const set of working) {
          const estimate = estimateOneRepMax(set.weightKg, set.reps);
          if (estimate > bestEstimate) {
            bestEstimate = estimate;
            top = set;
          }
        }
        return {
          sessionId: session.id,
          dayKey: session.dayKey,
          topWeightKg: top?.weightKg ?? null,
          topReps: top?.reps ?? null,
          estimatedOneRepMax: bestEstimate > 0 ? Math.round(bestEstimate * 10) / 10 : null,
          volumeKg: volumeOf(sets),
          setCount: workingSetCount(sets),
        };
      });

    return NextResponse.json({ exercise, points });
  },
);

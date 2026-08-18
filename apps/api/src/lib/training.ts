// Workout helpers: ownership loading, the "last time / this time" join, and
// the DTO shapes the app renders at the rack.
//
// The one interesting query here is `previousPerformance`. A lifter's next set
// is chosen by looking at the previous one, so that lookup is on the critical
// path of the main screen and must not turn into a request per exercise. It is
// a single CTE: rank every prior set of these exercises by how recent its
// session is, keep rank 1, which is exactly "the sets from the last time I did
// this movement" — per exercise, in one round trip.

import { and, asc, desc, eq, gte, inArray, isNotNull, lt, lte, ne, sql, type SQL } from "drizzle-orm";
import { db } from "@/db/client";
import {
  exercises,
  workoutRoutineExercises,
  workoutRoutines,
  workoutSessions,
  workoutSets,
} from "@/db/schema";
import { ApiError } from "./http";
import { volumeOf, workingSetCount } from "./training-math";

export { estimateOneRepMax, volumeOf, workingSetCount } from "./training-math";

export type ExerciseRow = typeof exercises.$inferSelect;
export type RoutineRow = typeof workoutRoutines.$inferSelect;
export type SessionRow = typeof workoutSessions.$inferSelect;
export type SetRow = typeof workoutSets.$inferSelect;

// ---------- ownership loaders ----------

export async function loadExercise(userId: string, id: string): Promise<ExerciseRow> {
  const row = await db.query.exercises.findFirst({
    where: and(eq(exercises.id, id), eq(exercises.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Exercise not found");
  return row;
}

export async function loadRoutine(userId: string, id: string): Promise<RoutineRow> {
  const row = await db.query.workoutRoutines.findFirst({
    where: and(eq(workoutRoutines.id, id), eq(workoutRoutines.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Routine not found");
  return row;
}

export async function loadSession(userId: string, id: string): Promise<SessionRow> {
  const row = await db.query.workoutSessions.findFirst({
    where: and(eq(workoutSessions.id, id), eq(workoutSessions.userId, userId)),
  });
  if (!row) throw new ApiError(404, "not_found", "Workout not found");
  return row;
}

// ---------- DTOs ----------

export interface SetDTO {
  id: string;
  exerciseId: string;
  setIndex: number;
  weightKg: number | null;
  reps: number | null;
  isWarmup: boolean;
  completedAt: Date;
}

export function setDTO(row: SetRow): SetDTO {
  return {
    id: row.id,
    exerciseId: row.exerciseId,
    setIndex: row.setIndex,
    weightKg: row.weightKg,
    reps: row.reps,
    isWarmup: row.isWarmup,
    completedAt: row.completedAt,
  };
}

export interface ExerciseTargetDTO {
  sets: number;
  repsLow: number | null;
  repsHigh: number | null;
  weightKg: number | null;
  restSeconds: number | null;
  notes: string | null;
}

export interface PreviousPerformanceDTO {
  sessionId: string;
  dayKey: string;
  sets: SetDTO[];
}

export interface PersonalBestDTO {
  weightKg: number | null;
  reps: number | null;
  dayKey: string;
}

export interface SessionExerciseDTO {
  exerciseId: string;
  name: string;
  muscleGroup: string | null;
  equipment: string | null;
  isBodyweight: boolean;
  /** From the routine. Null when the exercise was added ad hoc mid-workout. */
  target: ExerciseTargetDTO | null;
  sets: SetDTO[];
  previous: PreviousPerformanceDTO | null;
  best: PersonalBestDTO | null;
}

export interface SessionDetailDTO {
  id: string;
  routineId: string | null;
  title: string;
  dayKey: string;
  startedAt: Date;
  finishedAt: Date | null;
  notes: string | null;
  exercises: SessionExerciseDTO[];
  setCount: number;
  volumeKg: number;
}

export interface SessionSummaryDTO {
  id: string;
  routineId: string | null;
  title: string;
  dayKey: string;
  startedAt: Date;
  finishedAt: Date | null;
  notes: string | null;
  exerciseCount: number;
  setCount: number;
  volumeKg: number;
  durationMinutes: number | null;
}

// ---------- the "last time" join ----------

/**
 * For each of `exerciseIds`, the sets from the most recent session that is not
 * `excludeSessionId` and started before `before`. One query, ranked in the
 * database.
 */
export async function previousPerformance(
  userId: string,
  exerciseIds: string[],
  excludeSessionId: string,
  before: Date,
): Promise<Map<string, PreviousPerformanceDTO>> {
  const result = new Map<string, PreviousPerformanceDTO>();
  if (exerciseIds.length === 0) return result;

  const ranked = db.$with("ranked").as(
    db
      .select({
        id: workoutSets.id,
        exerciseId: workoutSets.exerciseId,
        sessionId: workoutSets.sessionId,
        setIndex: workoutSets.setIndex,
        weightKg: workoutSets.weightKg,
        reps: workoutSets.reps,
        isWarmup: workoutSets.isWarmup,
        completedAt: workoutSets.completedAt,
        dayKey: workoutSessions.dayKey,
        // dense_rank so every set of the winning session survives the filter.
        rank: sql<number>`dense_rank() over (
          partition by ${workoutSets.exerciseId}
          order by ${workoutSessions.startedAt} desc, ${workoutSessions.id} desc
        )`.as("rank"),
      })
      .from(workoutSets)
      .innerJoin(workoutSessions, eq(workoutSessions.id, workoutSets.sessionId))
      .where(
        and(
          eq(workoutSets.userId, userId),
          inArray(workoutSets.exerciseId, exerciseIds),
          ne(workoutSets.sessionId, excludeSessionId),
          lt(workoutSessions.startedAt, before),
        ),
      ),
  );

  const rows = await db
    .with(ranked)
    .select()
    .from(ranked)
    .where(eq(ranked.rank, 1))
    .orderBy(asc(ranked.exerciseId), asc(ranked.setIndex));

  for (const row of rows) {
    const existing = result.get(row.exerciseId);
    const set: SetDTO = {
      id: row.id,
      exerciseId: row.exerciseId,
      setIndex: row.setIndex,
      weightKg: row.weightKg,
      reps: row.reps,
      isWarmup: row.isWarmup,
      completedAt: row.completedAt,
    };
    if (existing) {
      existing.sets.push(set);
    } else {
      result.set(row.exerciseId, {
        sessionId: row.sessionId,
        dayKey: row.dayKey,
        sets: [set],
      });
    }
  }
  return result;
}

/**
 * Best working set per exercise, ranked by estimated 1RM so a heavier-but-
 * shorter set and a lighter-but-longer one are comparable.
 */
export async function personalBests(
  userId: string,
  exerciseIds: string[],
): Promise<Map<string, PersonalBestDTO>> {
  const result = new Map<string, PersonalBestDTO>();
  if (exerciseIds.length === 0) return result;

  const ranked = db.$with("ranked_best").as(
    db
      .select({
        exerciseId: workoutSets.exerciseId,
        weightKg: workoutSets.weightKg,
        reps: workoutSets.reps,
        dayKey: workoutSessions.dayKey,
        rank: sql<number>`row_number() over (
          partition by ${workoutSets.exerciseId}
          order by (coalesce(${workoutSets.weightKg}, 0) * (1 + coalesce(${workoutSets.reps}, 0) / 30.0)) desc,
                   ${workoutSessions.startedAt} desc
        )`.as("rank"),
      })
      .from(workoutSets)
      .innerJoin(workoutSessions, eq(workoutSessions.id, workoutSets.sessionId))
      .where(
        and(
          eq(workoutSets.userId, userId),
          inArray(workoutSets.exerciseId, exerciseIds),
          eq(workoutSets.isWarmup, false),
          isNotNull(workoutSets.reps),
        ),
      ),
  );

  const rows = await db.with(ranked).select().from(ranked).where(eq(ranked.rank, 1));
  for (const row of rows) {
    result.set(row.exerciseId, { weightKg: row.weightKg, reps: row.reps, dayKey: row.dayKey });
  }
  return result;
}

// ---------- routine detail ----------

export interface RoutineExerciseDTO {
  exerciseId: string;
  name: string;
  muscleGroup: string | null;
  equipment: string | null;
  isBodyweight: boolean;
  targetSets: number;
  targetRepsLow: number | null;
  targetRepsHigh: number | null;
  targetWeightKg: number | null;
  restSeconds: number | null;
  notes: string | null;
  sortOrder: number;
}

export interface RoutineDetailDTO {
  id: string;
  name: string;
  emoji: string | null;
  colorHex: string | null;
  notes: string | null;
  sortOrder: number;
  archived: boolean;
  exercises: RoutineExerciseDTO[];
}

/** The routine with its lines resolved to exercise names — the editor's load. */
export async function routineDetail(userId: string, id: string): Promise<RoutineDetailDTO> {
  const routine = await loadRoutine(userId, id);
  const lines = await db
    .select({ line: workoutRoutineExercises, exercise: exercises })
    .from(workoutRoutineExercises)
    .innerJoin(exercises, eq(exercises.id, workoutRoutineExercises.exerciseId))
    .where(eq(workoutRoutineExercises.routineId, id))
    .orderBy(asc(workoutRoutineExercises.sortOrder));

  return {
    id: routine.id,
    name: routine.name,
    emoji: routine.emoji,
    colorHex: routine.colorHex,
    notes: routine.notes,
    sortOrder: routine.sortOrder,
    archived: routine.archivedAt !== null,
    exercises: lines.map((row) => ({
      exerciseId: row.exercise.id,
      name: row.exercise.name,
      muscleGroup: row.exercise.muscleGroup,
      equipment: row.exercise.equipment,
      isBodyweight: row.exercise.isBodyweight,
      targetSets: row.line.targetSets,
      targetRepsLow: row.line.targetRepsLow,
      targetRepsHigh: row.line.targetRepsHigh,
      targetWeightKg: row.line.targetWeightKg,
      restSeconds: row.line.restSeconds,
      notes: row.line.notes,
      sortOrder: row.line.sortOrder,
    })),
  };
}

// ---------- session detail assembly ----------

/**
 * The training screen's whole payload: the routine's plan, what has been
 * logged so far, and what the same movements looked like last time.
 *
 * The exercise order is the routine's, with anything logged ad hoc appended —
 * so adding a movement mid-workout never reshuffles the list under your thumb.
 */
export async function buildSessionDetail(
  userId: string,
  session: SessionRow,
): Promise<SessionDetailDTO> {
  const [plan, loggedSets] = await Promise.all([
    session.routineId
      ? db
          .select({ line: workoutRoutineExercises, exercise: exercises })
          .from(workoutRoutineExercises)
          .innerJoin(exercises, eq(exercises.id, workoutRoutineExercises.exerciseId))
          .where(eq(workoutRoutineExercises.routineId, session.routineId))
          .orderBy(asc(workoutRoutineExercises.sortOrder))
      : Promise.resolve([]),
    db
      .select({ set: workoutSets, exercise: exercises })
      .from(workoutSets)
      .innerJoin(exercises, eq(exercises.id, workoutSets.exerciseId))
      .where(eq(workoutSets.sessionId, session.id))
      .orderBy(asc(workoutSets.setIndex), asc(workoutSets.completedAt)),
  ]);

  const ordered: { exercise: ExerciseRow; target: ExerciseTargetDTO | null }[] = plan.map((row) => ({
    exercise: row.exercise,
    target: {
      sets: row.line.targetSets,
      repsLow: row.line.targetRepsLow,
      repsHigh: row.line.targetRepsHigh,
      weightKg: row.line.targetWeightKg,
      restSeconds: row.line.restSeconds,
      notes: row.line.notes,
    },
  }));
  const seen = new Set(ordered.map((entry) => entry.exercise.id));
  for (const row of loggedSets) {
    if (seen.has(row.exercise.id)) continue;
    seen.add(row.exercise.id);
    ordered.push({ exercise: row.exercise, target: null });
  }

  const exerciseIds = ordered.map((entry) => entry.exercise.id);
  const [previous, bests] = await Promise.all([
    previousPerformance(userId, exerciseIds, session.id, session.startedAt),
    personalBests(userId, exerciseIds),
  ]);

  const setsByExercise = new Map<string, SetDTO[]>();
  for (const row of loggedSets) {
    const list = setsByExercise.get(row.set.exerciseId) ?? [];
    list.push(setDTO(row.set));
    setsByExercise.set(row.set.exerciseId, list);
  }

  const allSets = loggedSets.map((row) => row.set);
  return {
    id: session.id,
    routineId: session.routineId,
    title: session.title,
    dayKey: session.dayKey,
    startedAt: session.startedAt,
    finishedAt: session.finishedAt,
    notes: session.notes,
    exercises: ordered.map((entry) => ({
      exerciseId: entry.exercise.id,
      name: entry.exercise.name,
      muscleGroup: entry.exercise.muscleGroup,
      equipment: entry.exercise.equipment,
      isBodyweight: entry.exercise.isBodyweight,
      target: entry.target,
      sets: setsByExercise.get(entry.exercise.id) ?? [],
      previous: previous.get(entry.exercise.id) ?? null,
      best: bests.get(entry.exercise.id) ?? null,
    })),
    setCount: workingSetCount(allSets),
    volumeKg: volumeOf(allSets),
  };
}

// ---------- session list ----------

export async function listSessionSummaries(
  userId: string,
  options: { from?: string; to?: string; limit?: number } = {},
): Promise<SessionSummaryDTO[]> {
  const conditions: SQL[] = [eq(workoutSessions.userId, userId)];
  if (options.from) conditions.push(gte(workoutSessions.dayKey, options.from));
  if (options.to) conditions.push(lte(workoutSessions.dayKey, options.to));

  const sessionRows = await db
    .select()
    .from(workoutSessions)
    .where(and(...conditions))
    .orderBy(desc(workoutSessions.dayKey), desc(workoutSessions.startedAt))
    .limit(options.limit ?? 60);

  if (sessionRows.length === 0) return [];

  const setRows = await db
    .select()
    .from(workoutSets)
    .where(
      inArray(
        workoutSets.sessionId,
        sessionRows.map((row) => row.id),
      ),
    );

  const grouped = new Map<string, SetRow[]>();
  for (const set of setRows) {
    const list = grouped.get(set.sessionId) ?? [];
    list.push(set);
    grouped.set(set.sessionId, list);
  }

  return sessionRows.map((session) => {
    const sets = grouped.get(session.id) ?? [];
    return {
      id: session.id,
      routineId: session.routineId,
      title: session.title,
      dayKey: session.dayKey,
      startedAt: session.startedAt,
      finishedAt: session.finishedAt,
      notes: session.notes,
      exerciseCount: new Set(sets.map((set) => set.exerciseId)).size,
      setCount: workingSetCount(sets),
      volumeKg: volumeOf(sets),
      durationMinutes: session.finishedAt
        ? Math.max(
            0,
            Math.round((session.finishedAt.getTime() - session.startedAt.getTime()) / 60000),
          )
        : null,
    };
  });
}

// ---------- routine writes ----------

/**
 * Replaces a routine's exercise list wholesale. Duplicated exercises are
 * dropped rather than rejected: the editor can produce one by accident, and
 * losing the duplicate is a better outcome than losing the save.
 */
export async function replaceRoutineExercises(
  userId: string,
  routineId: string,
  lines: {
    exerciseId: string;
    targetSets?: number;
    targetRepsLow?: number | null;
    targetRepsHigh?: number | null;
    targetWeightKg?: number | null;
    restSeconds?: number | null;
    notes?: string | null;
  }[],
): Promise<void> {
  await db
    .delete(workoutRoutineExercises)
    .where(eq(workoutRoutineExercises.routineId, routineId));

  const seen = new Set<string>();
  const values = lines
    .filter((line) => {
      if (seen.has(line.exerciseId)) return false;
      seen.add(line.exerciseId);
      return true;
    })
    .map((line, index) => ({
      userId,
      routineId,
      exerciseId: line.exerciseId,
      targetSets: line.targetSets ?? 3,
      targetRepsLow: line.targetRepsLow ?? null,
      targetRepsHigh: line.targetRepsHigh ?? null,
      targetWeightKg: line.targetWeightKg ?? null,
      restSeconds: line.restSeconds ?? null,
      notes: line.notes ?? null,
      sortOrder: index,
    }));

  if (values.length === 0) return;

  // Every id must belong to this user — otherwise a crafted request could
  // pull another account's exercise into a routine.
  const owned = await db
    .select({ id: exercises.id })
    .from(exercises)
    .where(and(eq(exercises.userId, userId), inArray(exercises.id, [...seen])));
  if (owned.length !== seen.size) {
    throw new ApiError(400, "unknown_exercise", "One or more exercises do not exist");
  }

  await db.insert(workoutRoutineExercises).values(values);
}

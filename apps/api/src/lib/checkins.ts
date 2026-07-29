// Improvement-area check-in logic: which week a check-in belongs to and
// whether an area is due. Pure (no db) so it unit-tests without DATABASE_URL.

import { weekStart, type DayKey } from "./daykey";

/** The weekKey (Monday) a check-in on `dayKey` belongs to. */
export function weekKeyFor(dayKey: DayKey): DayKey {
  return weekStart(dayKey);
}

export interface AreaLike {
  id: string;
  name: string;
  emoji: string | null;
  betterLooksLike: string | null;
  sortOrder: number;
  archivedAt: Date | null;
}

export interface CheckinLike {
  id: string;
  weekKey: string;
  dayKey: string;
  createdAt: Date;
}

export interface ImprovementAreaDTO {
  id: string;
  name: string;
  emoji: string | null;
  betterLooksLike: string | null;
  sortOrder: number;
  archived: boolean;
  /** Active area with no check-in for the current week. */
  dueThisWeek: boolean;
  thisWeek: { id: string; dayKey: string } | null;
  lastCheckinAt: string | null; // dayKey of the most recent check-in
}

export function buildAreaDTO(
  area: AreaLike,
  latestCheckin: CheckinLike | null,
  currentWeekKey: DayKey,
): ImprovementAreaDTO {
  const thisWeek =
    latestCheckin && latestCheckin.weekKey === currentWeekKey
      ? { id: latestCheckin.id, dayKey: latestCheckin.dayKey }
      : null;
  return {
    id: area.id,
    name: area.name,
    emoji: area.emoji,
    betterLooksLike: area.betterLooksLike,
    sortOrder: area.sortOrder,
    archived: area.archivedAt !== null,
    dueThisWeek: area.archivedAt === null && thisWeek === null,
    thisWeek,
    lastCheckinAt: latestCheckin?.dayKey ?? null,
  };
}

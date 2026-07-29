// Day & week math. A "dayKey" is a YYYY-MM-DD calendar date in the user's
// timezone after shifting the day boundary (default 3 AM: 02:30 belongs to the
// previous day). The server is the single source of truth for persisted dayKeys;
// the Swift app mirrors this logic for display only.

export type DayKey = string; // YYYY-MM-DD

const DAY_MS = 24 * 60 * 60 * 1000;

/** Calendar date of `instant` in `timezone`, as YYYY-MM-DD. */
function calendarDateInTz(instant: Date, timezone: string): DayKey {
  // en-CA formats as YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(instant);
}

/**
 * The dayKey an instant belongs to, honoring the day-boundary hour.
 * Shifting the instant back by `boundaryHour` hours and taking the local
 * calendar date is equivalent to comparing local wall time against the
 * boundary. EU DST transitions (02:00–03:00 local) sit inside the shifted
 * window; the spec accepts the (harmless) ambiguity there.
 */
export function dayKeyFor(instant: Date, timezone: string, boundaryHour: number): DayKey {
  const shifted = new Date(instant.getTime() - boundaryHour * 60 * 60 * 1000);
  return calendarDateInTz(shifted, timezone);
}

/** Parse a dayKey to a UTC Date at midnight (for pure calendar arithmetic). */
export function dayKeyToUTC(dayKey: DayKey): Date {
  const [y, m, d] = dayKey.split("-").map(Number);
  if (!y || !m || !d) throw new Error(`Invalid dayKey: ${dayKey}`);
  return new Date(Date.UTC(y, m - 1, d));
}

export function isValidDayKey(dayKey: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey)) return false;
  const date = dayKeyToUTC(dayKey);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === dayKey;
}

export function addDays(dayKey: DayKey, days: number): DayKey {
  const date = dayKeyToUTC(dayKey);
  return new Date(date.getTime() + days * DAY_MS).toISOString().slice(0, 10);
}

/** b - a in whole days. */
export function diffDays(a: DayKey, b: DayKey): number {
  return Math.round((dayKeyToUTC(b).getTime() - dayKeyToUTC(a).getTime()) / DAY_MS);
}

/** ISO weekday of a dayKey: Mon=1 .. Sun=7. */
export function isoWeekday(dayKey: DayKey): number {
  const jsDay = dayKeyToUTC(dayKey).getUTCDay(); // Sun=0 .. Sat=6
  return jsDay === 0 ? 7 : jsDay;
}

/** Monday of the dayKey's ISO week. */
export function weekStart(dayKey: DayKey): DayKey {
  return addDays(dayKey, 1 - isoWeekday(dayKey));
}

/** Sunday of the dayKey's ISO week. */
export function weekEnd(dayKey: DayKey): DayKey {
  return addDays(weekStart(dayKey), 6);
}

/** Days elapsed in the week including this day: Mon=1 .. Sun=7. */
export function elapsedDayOfWeek(dayKey: DayKey): number {
  return isoWeekday(dayKey);
}


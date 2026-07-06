/**
 * Date helpers operating on the notion of a "logical day": a local calendar
 * date in a given timezone whose boundary can be shifted past midnight
 * (default 03:00). All functions are pure and dependency-free.
 */

/**
 * Returns the `YYYY-MM-DD` string of the *logical* day for `now` in `timeZone`.
 *
 * The wall-clock time in `timeZone` is computed with Intl (no external deps).
 * When that wall-clock time is strictly before `dayEndsAt` (a `"HH:MM"` string,
 * default `"03:00"`), the logical day is the previous calendar date.
 *
 * Example: at 01:30 local on 2026-07-07 with boundary 03:00, the logical day
 * is still 2026-07-06.
 */
export function localDateString(
  now: Date,
  timeZone: string,
  dayEndsAt = "03:00",
): string {
  const parts = wallClockParts(now, timeZone);
  const boundaryMinutes = parseHhMm(dayEndsAt);
  const nowMinutes = parts.hour * 60 + parts.minute;

  const dateStr = `${pad4(parts.year)}-${pad2(parts.month)}-${pad2(parts.day)}`;
  if (nowMinutes < boundaryMinutes) {
    return addDays(dateStr, -1);
  }
  return dateStr;
}

/**
 * ISO weekday for a `YYYY-MM-DD` string: 1 = Monday .. 7 = Sunday.
 * Computed via `Date.UTC` so it is independent of the host timezone.
 */
export function isoWeekday(dateStr: string): number {
  const { year, month, day } = parseDateStr(dateStr);
  const jsDay = new Date(Date.UTC(year, month - 1, day)).getUTCDay(); // 0=Sun..6=Sat
  return jsDay === 0 ? 7 : jsDay;
}

/**
 * Adds `days` (may be negative) to a `YYYY-MM-DD` string, returning a
 * `YYYY-MM-DD` string. Timezone-safe (operates in UTC).
 */
export function addDays(dateStr: string, days: number): string {
  const { year, month, day } = parseDateStr(dateStr);
  const ms = Date.UTC(year, month - 1, day) + days * 86_400_000;
  const d = new Date(ms);
  return `${pad4(d.getUTCFullYear())}-${pad2(d.getUTCMonth() + 1)}-${pad2(
    d.getUTCDate(),
  )}`;
}

interface WallClockParts {
  year: number;
  month: number; // 1..12
  day: number;
  hour: number; // 0..23
  minute: number;
}

function wallClockParts(now: Date, timeZone: string): WallClockParts {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const parts = fmt.formatToParts(now);
  const get = (type: Intl.DateTimeFormatPartTypes): number => {
    const p = parts.find((x) => x.type === type);
    if (!p) throw new Error(`Missing date part: ${type}`);
    return Number(p.value);
  };
  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour: get("hour"),
    minute: get("minute"),
  };
}

function parseDateStr(dateStr: string): {
  year: number;
  month: number;
  day: number;
} {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr);
  if (!m) throw new Error(`Invalid date string: ${dateStr}`);
  return { year: Number(m[1]), month: Number(m[2]), day: Number(m[3]) };
}

function parseHhMm(value: string): number {
  const m = /^(\d{2}):(\d{2})$/.exec(value);
  if (!m) throw new Error(`Invalid HH:MM string: ${value}`);
  return Number(m[1]) * 60 + Number(m[2]);
}

function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

function pad4(n: number): string {
  return String(n).padStart(4, "0");
}

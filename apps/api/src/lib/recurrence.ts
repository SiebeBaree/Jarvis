// Recurrence materialization: templates are expanded into concrete task rows
// up to a horizon dayKey. `lastGeneratedThrough` is the high-water mark so the
// same occurrence is never generated twice (backed up by a unique index on
// (templateId, templateDate)).

import type { RecurrenceRule } from "../db/schema";
import { addDays, dayKeyToUTC, diffDays, isoWeekday, weekStart, type DayKey } from "./daykey";

export interface RecurrenceWindow {
  rule: RecurrenceRule;
  startDate: DayKey;
  endDate: DayKey | null;
  /** Occurrences on or before this dayKey were already generated. */
  lastGeneratedThrough: DayKey | null;
  /** Generate occurrences up to and including this dayKey. */
  through: DayKey;
}

/** Last day of a dayKey's month, as a day-of-month number (28-31). */
function lastDayOfMonth(year: number, month1: number): number {
  return new Date(Date.UTC(year, month1, 0)).getUTCDate();
}

function monthlyOccurrence(year: number, month1: number, byMonthDay: number): DayKey {
  const day = Math.min(byMonthDay, lastDayOfMonth(year, month1)); // clamp: Jan 31 → Feb 28
  return `${year.toString().padStart(4, "0")}-${month1.toString().padStart(2, "0")}-${day
    .toString()
    .padStart(2, "0")}`;
}

/**
 * All occurrence dayKeys in (lastGeneratedThrough, through], respecting the
 * template's start/end dates. Deterministic and pure.
 */
export function occurrencesToGenerate(window: RecurrenceWindow): DayKey[] {
  const { rule, startDate, endDate, lastGeneratedThrough, through } = window;
  const from = lastGeneratedThrough ?? addDays(startDate, -1); // exclusive lower bound
  const upper = endDate !== null && endDate < through ? endDate : through;
  if (upper <= from) return [];

  const out: DayKey[] = [];
  const push = (day: DayKey) => {
    if (day > from && day <= upper && day >= startDate) out.push(day);
  };

  switch (rule.freq) {
    case "daily": {
      const interval = Math.max(1, rule.interval);
      // First occurrence at startDate, then every `interval` days.
      const gap = Math.max(0, diffDays(startDate, from) + 1);
      let k = Math.max(0, Math.ceil(gap / interval) - 1); // start a step early, `push` filters
      for (;;) {
        const day = addDays(startDate, k * interval);
        if (day > upper) break;
        push(day);
        k++;
      }
      break;
    }
    case "weekly": {
      const interval = Math.max(1, rule.interval);
      const anchorWeek = weekStart(startDate);
      const weekdays = [...new Set(rule.byWeekday)].filter((d) => d >= 1 && d <= 7).sort();
      if (weekdays.length === 0) return [];
      for (let week = anchorWeek; week <= upper; week = addDays(week, 7 * interval)) {
        for (const wd of weekdays) push(addDays(week, wd - 1));
      }
      break;
    }
    case "monthly": {
      const interval = Math.max(1, rule.interval);
      const start = dayKeyToUTC(startDate);
      let year = start.getUTCFullYear();
      let month1 = start.getUTCMonth() + 1;
      for (;;) {
        const day = monthlyOccurrence(year, month1, rule.byMonthDay);
        if (day > upper) break;
        push(day);
        month1 += interval;
        year += Math.floor((month1 - 1) / 12);
        month1 = ((month1 - 1) % 12) + 1;
      }
      break;
    }
  }
  return out;
}

/** Next occurrence strictly after `after`, or null if the template has ended. */
export function nextOccurrence(
  rule: RecurrenceRule,
  startDate: DayKey,
  endDate: DayKey | null,
  after: DayKey,
): DayKey | null {
  // Look ahead far enough for any rule (monthly interval up to 12 → 3 years is plenty).
  const horizon = addDays(after, 1100);
  const upper = endDate !== null && endDate < horizon ? endDate : horizon;
  const occurrences = occurrencesToGenerate({
    rule,
    startDate,
    endDate,
    lastGeneratedThrough: after,
    through: upper,
  });
  return occurrences[0] ?? null;
}

// Re-export for callers that need weekday math alongside recurrence.
export { isoWeekday };

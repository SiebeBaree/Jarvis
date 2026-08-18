// The text of the daily check-in nudge.
//
// One notification a day is the whole budget, so the copy has to earn it: it
// says something true about where the day actually stands rather than the same
// sentence every evening. Categories are a priority ladder, not a scoring
// function, so the reason a given message appeared is always answerable.
//
// Voice: calm, dry, literal. No exclamation marks, no cheerleading, no guilt
// about a day that went badly, and no dashes of any kind. Mood is described in
// words because the stored 0-100 value is not the 1-5 scale the app renders.

import type { DayKey } from "../daykey";

export type CheckinNudgeData = {
  dayKey: DayKey;
  /** Yesterday's mood, 0-100 canonical. null = not logged. */
  yesterdayMood: number | null;
  /** Open tasks whose due date is today. */
  openTasksToday: number;
  /** Open tasks whose due date has already passed. */
  overdueTasks: number;
  /** Longest run among the daily habits currently going. */
  bestActiveStreak: { habitName: string; days: number } | null;
  /** False when the user has never logged a mood at all. */
  hasAnyMoodEntry: boolean;
};

export type NudgeCategory =
  | "first_entry"
  | "yesterday_bad"
  | "overdue"
  | "streak"
  | "busy_day"
  | "yesterday_good"
  | "generic";

export type ComposedNudge = {
  title: string;
  body: string;
  /** `category:index`, stored on the log row so a delivered message is traceable. */
  template: string;
  category: NudgeCategory;
};

// Thresholds sit here rather than inline so the tests and the ladder agree.
const BAD_MOOD_AT_OR_BELOW = 40;
const GOOD_MOOD_AT_OR_ABOVE = 70;
const STREAK_WORTH_MENTIONING = 3;
const BUSY_DAY_TASKS = 4;

type Variant = (data: CheckinNudgeData) => { title: string; body: string };

const plural = (n: number, one: string, many: string) => (n === 1 ? one : many);

// Non-empty by construction, so picking a variant never has to handle a miss.
const CATALOGUE: Record<NudgeCategory, [Variant, ...Variant[]]> = {
  first_entry: [
    () => ({
      title: "First check-in",
      body: "You have not logged a mood yet. Open Jarvis and record how today felt. It takes about ten seconds.",
    }),
    () => ({
      title: "First check-in",
      body: "Nothing is logged yet. Setting today's mood is the one entry that starts the record.",
    }),
  ],
  yesterday_bad: [
    () => ({
      title: "Daily check-in",
      body: "Yesterday was a rough one. Today counts separately. Log how it went.",
    }),
    () => ({
      title: "Daily check-in",
      body: "New day, clean slate. Yesterday's number does not carry over. Record today's when you have a moment.",
    }),
    () => ({
      title: "Daily check-in",
      body: "Yesterday landed low. Today is still unlogged, and it gets its own entry.",
    }),
  ],
  overdue: [
    (d) => ({
      title: "Daily check-in",
      body: `${d.overdueTasks} ${plural(d.overdueTasks, "task is", "tasks are")} overdue and today's mood is not logged. The mood entry is the ten second one, so start there.`,
    }),
    (d) => ({
      title: "Daily check-in",
      body: `Today's check-in is still open, and ${d.overdueTasks} ${plural(d.overdueTasks, "task", "tasks")} slipped past ${plural(d.overdueTasks, "its", "their")} date. Log the mood first, then decide about the rest.`,
    }),
  ],
  streak: [
    (d) => ({
      title: "Daily check-in",
      body: `${d.bestActiveStreak?.habitName} is at ${d.bestActiveStreak?.days} days in a row. Today's mood entry is still open.`,
    }),
    (d) => ({
      title: "Daily check-in",
      body: `You have kept ${d.bestActiveStreak?.habitName} going for ${d.bestActiveStreak?.days} days. The mood log for today is the remaining item.`,
    }),
  ],
  busy_day: [
    (d) => ({
      title: "Daily check-in",
      body: `${d.openTasksToday} ${plural(d.openTasksToday, "task is", "tasks are")} still open for today. Check off what you finished, then log how it felt.`,
    }),
    (d) => ({
      title: "Daily check-in",
      body: `A full list today: ${d.openTasksToday} ${plural(d.openTasksToday, "task", "tasks")} still marked open. Tick off anything you did and record the day.`,
    }),
  ],
  yesterday_good: [
    () => ({
      title: "Daily check-in",
      body: "Yesterday went well. Log today's mood to keep the record complete.",
    }),
    () => ({
      title: "Daily check-in",
      body: "Good day yesterday. Add today's entry so the trend stays honest.",
    }),
  ],
  generic: [
    () => ({
      title: "Daily check-in",
      body: "Today's mood entry is empty. Ten seconds to fill it in.",
    }),
    () => ({
      title: "Daily check-in",
      body: "You have not checked in today. Log a mood before the day rolls over.",
    }),
    () => ({
      title: "Daily check-in",
      body: "One item left for today: how it felt. Open Jarvis and record it.",
    }),
  ],
};

/** First match wins, so the message is the most specific thing that is true. */
function categoryFor(data: CheckinNudgeData): NudgeCategory {
  if (!data.hasAnyMoodEntry) return "first_entry";
  if (data.yesterdayMood !== null && data.yesterdayMood <= BAD_MOOD_AT_OR_BELOW) return "yesterday_bad";
  if (data.overdueTasks >= 1) return "overdue";
  if (data.bestActiveStreak && data.bestActiveStreak.days >= STREAK_WORTH_MENTIONING) return "streak";
  if (data.openTasksToday >= BUSY_DAY_TASKS) return "busy_day";
  if (data.yesterdayMood !== null && data.yesterdayMood >= GOOD_MOOD_AT_OR_ABOVE) return "yesterday_good";
  return "generic";
}

/**
 * FNV-1a over the dayKey. Rotation has to be deterministic: the cron can retry
 * within the same day, and a message that changed on retry would be a second
 * different notification for the same nudge.
 */
function hashDayKey(dayKey: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < dayKey.length; i++) {
    hash ^= dayKey.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash;
}

export function composeCheckinNudge(data: CheckinNudgeData): ComposedNudge {
  const category = categoryFor(data);
  const variants = CATALOGUE[category];
  const index = hashDayKey(data.dayKey) % variants.length;
  const variant = variants[index] ?? variants[0];
  const { title, body } = variant(data);
  return { title, body, template: `${category}:${index}`, category };
}

/** Every variant, rendered with sample data. Exported for the persona test. */
export function allVariantsForLint(): { category: NudgeCategory; title: string; body: string }[] {
  const sample: CheckinNudgeData = {
    dayKey: "2026-08-18",
    yesterdayMood: 50,
    openTasksToday: 5,
    overdueTasks: 3,
    bestActiveStreak: { habitName: "Gym", days: 12 },
    hasAnyMoodEntry: true,
  };
  const singular: CheckinNudgeData = { ...sample, openTasksToday: 1, overdueTasks: 1 };
  const out: { category: NudgeCategory; title: string; body: string }[] = [];
  for (const [category, variants] of Object.entries(CATALOGUE)) {
    for (const variant of variants) {
      for (const data of [sample, singular]) {
        const { title, body } = variant(data);
        out.push({ category: category as NudgeCategory, title, body });
      }
    }
  }
  return out;
}

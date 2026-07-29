import { sql } from "drizzle-orm";
import {
  boolean,
  date,
  index,
  integer,
  jsonb,
  numeric,
  pgEnum,
  pgTable,
  primaryKey,
  smallint,
  text,
  time,
  timestamp,
  uniqueIndex,
  uuid,
  varchar,
  type AnyPgColumn,
} from "drizzle-orm/pg-core";

// Conventions:
// - `date` columns store dayKeys: the calendar date after applying the user's
//   3 AM day boundary in their timezone. The server computes all persisted dayKeys.
// - `timestamptz` for real instants.
// - Everything is keyed by userId even though the app is single-user; singletons
//   (settings, vision, user_profile) use userId as their PK.

// ---------- enums ----------
export const goalStatus = pgEnum("goal_status", ["active", "achieved", "dropped"]);
export const goalHorizon = pgEnum("goal_horizon", ["short", "long"]);
export const taskStatus = pgEnum("task_status", ["open", "done", "cancelled"]);
export const taskPriority = pgEnum("task_priority", ["low", "medium", "high"]);
export const habitType = pgEnum("habit_type", ["daily", "multi_daily", "weekly_frequency"]);

// ---------- auth ----------
export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(), // argon2id
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const sessions = pgTable("sessions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  tokenHash: text("token_hash").notNull().unique(), // sha256 hex of the raw 256-bit token
  deviceName: text("device_name"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  lastUsedAt: timestamp("last_used_at", { withTimezone: true }).notNull().defaultNow(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }), // null = active; long-lived, no expiry
});

// ---------- settings (singleton per user) ----------
export type ScoreWeights = { tasks: number; habits: number; feel: number };

export const settings = pgTable("settings", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  timezone: text("timezone").notNull().default("Europe/Brussels"),
  dayBoundaryHour: smallint("day_boundary_hour").notNull().default(3),
  weekStartsOn: smallint("week_starts_on").notNull().default(1), // 1 = Monday (ISO)
  scoreWeights: jsonb("score_weights")
    .$type<ScoreWeights>()
    .notNull()
    .default(sql`'{"tasks":40,"habits":40,"feel":20}'::jsonb`),
  moodScaleMax: smallint("mood_scale_max").notNull().default(5), // UI renders 1..5; stored 0..100
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// ---------- areas (user-defined life areas, e.g. Business / Appearance / Social) ----------
export const areas = pgTable("areas", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  emoji: varchar("emoji", { length: 16 }),
  colorHex: varchar("color_hex", { length: 9 }),
  sortOrder: integer("sort_order").notNull().default(0),
  archivedAt: timestamp("archived_at", { withTimezone: true }),
}, (t) => [uniqueIndex("areas_user_name_uq").on(t.userId, t.name)]);

// ---------- goals ----------
// A goal is a thing the user is trying to reach by a date. Two independent
// progress signals sit on it:
//
//   time     — startDate → targetDate against today; always available.
//   progress — how far along the work is. Numeric when the goal carries a
//              measurable value (0 → 10000 €, 92 → 80 kg), otherwise the
//              fraction of its milestones that are done, otherwise absent.
//
// Comparing the two is the whole point: 70% of the time spent for 40% of the
// goal is the signal the user opens the tab to see.

export const goals = pgTable("goals", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  areaId: uuid("area_id").references(() => areas.id, { onDelete: "set null" }),
  title: text("title").notNull(),
  description: text("description"),
  horizon: goalHorizon("horizon").notNull().default("short"),
  status: goalStatus("status").notNull().default("active"),
  startDate: date("start_date").notNull(),
  targetDate: date("target_date").notNull(),
  // All three null = untracked (milestones or nothing carry the progress).
  // startValue is the baseline, so "lose weight" (92 → 80) reads as 0% at the
  // start rather than 1150%, and a downward goal needs no special casing.
  unit: text("unit"),
  startValue: numeric("start_value", { precision: 14, scale: 3, mode: "number" }),
  targetValue: numeric("target_value", { precision: 14, scale: 3, mode: "number" }),
  currentValue: numeric("current_value", { precision: 14, scale: 3, mode: "number" }),
  sortOrder: integer("sort_order").notNull().default(0),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("goals_user_status_idx").on(t.userId, t.status)]);

export const goalMilestones = pgTable("goal_milestones", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  goalId: uuid("goal_id")
    .notNull()
    .references(() => goals.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  doneAt: timestamp("done_at", { withTimezone: true }),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("goal_milestones_goal_idx").on(t.goalId, t.sortOrder)]);

// ---------- tasks ----------
// User-defined task categories (work, personal, household...) — TickTick-style
// lists: purely organizational, never enter scoring.
export const taskCategories = pgTable("task_categories", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  emoji: varchar("emoji", { length: 16 }),
  colorHex: varchar("color_hex", { length: 9 }),
  sortOrder: integer("sort_order").notNull().default(0),
  archivedAt: timestamp("archived_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [uniqueIndex("task_categories_user_name_uq").on(t.userId, t.name)]);

export type RecurrenceRule =
  | { freq: "daily"; interval: number } // every N days
  | { freq: "weekly"; interval: number; byWeekday: number[] } // ISO weekdays 1-7
  | { freq: "monthly"; interval: number; byMonthDay: number }; // 1-31, clamped to month end

export const recurrenceTemplates = pgTable("recurrence_templates", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  notes: text("notes"),
  priority: taskPriority("priority").notNull().default("medium"),
  categoryId: uuid("category_id").references(() => taskCategories.id, { onDelete: "set null" }),
  dueTime: time("due_time"),
  rule: jsonb("rule").$type<RecurrenceRule>().notNull(),
  startDate: date("start_date").notNull(),
  endDate: date("end_date"), // null = forever
  pausedAt: timestamp("paused_at", { withTimezone: true }),
  lastGeneratedThrough: date("last_generated_through"), // materialization high-water mark
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const tasks = pgTable("tasks", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  notes: text("notes"),
  dueDate: date("due_date"), // dayKey; null = inbox/someday
  dueTime: time("due_time"),
  priority: taskPriority("priority").notNull().default("medium"),
  status: taskStatus("status").notNull().default("open"),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  categoryId: uuid("category_id").references(() => taskCategories.id, { onDelete: "set null" }),
  parentTaskId: uuid("parent_task_id").references((): AnyPgColumn => tasks.id, {
    onDelete: "cascade",
  }),
  templateId: uuid("template_id").references(() => recurrenceTemplates.id, {
    onDelete: "cascade",
  }),
  templateDate: date("template_date"), // occurrence key for dedupe
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  index("tasks_user_due_idx").on(t.userId, t.dueDate, t.status),
  index("tasks_user_category_idx").on(t.userId, t.categoryId),
  index("tasks_parent_idx").on(t.parentTaskId),
  uniqueIndex("tasks_template_occurrence_uq")
    .on(t.templateId, t.templateDate)
    .where(sql`template_id IS NOT NULL`),
]);

// ---------- habits ----------
export const habits = pgTable("habits", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  icon: text("icon"), // SF Symbol name
  colorHex: varchar("color_hex", { length: 9 }),
  type: habitType("type").notNull(),
  // daily: always 1. multi_daily: N per day (>=2). weekly_frequency: N per week (1-7).
  targetReps: integer("target_reps").notNull().default(1),
  // ISO weekdays; soft defaults for weekly habits. Cosmetic only — never used in scoring.
  plannedDays: jsonb("planned_days").$type<number[]>().notNull().default(sql`'[]'::jsonb`),
  areaId: uuid("area_id").references(() => areas.id, { onDelete: "set null" }),
  startDate: date("start_date").notNull(), // counts toward the score from this dayKey
  pausedAt: timestamp("paused_at", { withTimezone: true }), // paused = excluded from scoring
  archivedAt: timestamp("archived_at", { withTimezone: true }),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("habits_user_idx").on(t.userId, t.archivedAt)]);

export const habitCompletions = pgTable("habit_completions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  habitId: uuid("habit_id")
    .notNull()
    .references(() => habits.id, { onDelete: "cascade" }),
  dayKey: date("day_key").notNull(),
  completedAt: timestamp("completed_at", { withTimezone: true }).notNull().defaultNow(),
  // One row per rep; reps(habit, day) = COUNT(*). Undo = delete the latest row.
}, (t) => [
  index("hc_habit_day_idx").on(t.habitId, t.dayKey),
  index("hc_user_day_idx").on(t.userId, t.dayKey),
]);

// ---------- mood ----------
export const moodEntries = pgTable("mood_entries", {
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  dayKey: date("day_key").notNull(),
  value: smallint("value").notNull(), // 0-100 canonical
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [primaryKey({ columns: [t.userId, t.dayKey] })]);

// ---------- daily score snapshots ----------
export type ScoreBreakdown = {
  tasks: { taskId: string; credit: number; late: boolean }[];
  habits: {
    habitId: string;
    credit: number;
    reps: number;
    expected: number;
    reconciled: boolean;
  }[];
};

// ---------- improvement areas & weekly photo check-ins ----------
// Self-improvement areas (posture, clothing, teeth...). One photo check-in per
// area per week (weekKey = that week's Monday), so progress is visible by
// comparing shots side by side. Never feeds the daily score.

export const improvementAreas = pgTable("improvement_areas", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  emoji: varchar("emoji", { length: 16 }),
  // What "better" looks like, in the user's words — the yardstick to hold a
  // new photo against.
  betterLooksLike: text("better_looks_like"),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  archivedAt: timestamp("archived_at", { withTimezone: true }),
}, (t) => [uniqueIndex("improvement_areas_user_name_uq").on(t.userId, t.name)]);

export const areaCheckins = pgTable("area_checkins", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  areaId: uuid("area_id")
    .notNull()
    .references(() => improvementAreas.id, { onDelete: "cascade" }),
  weekKey: date("week_key").notNull(), // Monday of the check-in's week
  dayKey: date("day_key").notNull(),
  blobKey: text("blob_key").notNull(), // Vercel Blob pathname (private store)
  blobUrl: text("blob_url").notNull(),
  contentType: text("content_type").notNull(),
  sizeBytes: integer("size_bytes").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [uniqueIndex("area_checkins_week_uq").on(t.areaId, t.weekKey)]);

// ---------- body metrics & progress photos ----------

export const metricTypes = pgTable("metric_types", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(), // "Weight", "Body fat"
  unit: text("unit").notNull(), // "kg", "%"
  decimals: smallint("decimals").notNull().default(1),
  goalValue: numeric("goal_value", { precision: 10, scale: 3, mode: "number" }),
  goalDirection: text("goal_direction"), // "up" | "down" | null
  sortOrder: integer("sort_order").notNull().default(0),
  archivedAt: timestamp("archived_at", { withTimezone: true }),
}, (t) => [uniqueIndex("metric_types_name_uq").on(t.userId, t.name)]);

export const metricEntries = pgTable("metric_entries", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  metricTypeId: uuid("metric_type_id")
    .notNull()
    .references(() => metricTypes.id, { onDelete: "cascade" }),
  dayKey: date("day_key").notNull(),
  value: numeric("value", { precision: 10, scale: 3, mode: "number" }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [uniqueIndex("metric_entries_type_day_uq").on(t.metricTypeId, t.dayKey)]);

export const progressPhotos = pgTable("progress_photos", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  blobKey: text("blob_key").notNull(), // Vercel Blob pathname
  blobUrl: text("blob_url").notNull(), // unguessable blob URL
  angle: text("angle").notNull().default("front"), // user-defined label, reused
  dayKey: date("day_key").notNull(),
  contentType: text("content_type").notNull(),
  sizeBytes: integer("size_bytes").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("photos_user_day_idx").on(t.userId, t.dayKey)]);

export const dailyScores = pgTable("daily_scores", {
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  dayKey: date("day_key").notNull(),
  total: numeric("total", { precision: 5, scale: 2, mode: "number" }), // null = nothing applicable that day
  taskPoints: numeric("task_points", { precision: 5, scale: 2, mode: "number" }), // null = not applicable
  habitPoints: numeric("habit_points", { precision: 5, scale: 2, mode: "number" }),
  feelPoints: numeric("feel_points", { precision: 5, scale: 2, mode: "number" }),
  applicableWeight: numeric("applicable_weight", { precision: 5, scale: 2, mode: "number" }).notNull(),
  breakdown: jsonb("breakdown").$type<ScoreBreakdown>().notNull(),
  isFinal: boolean("is_final").notNull().default(false),
  computedAt: timestamp("computed_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [primaryKey({ columns: [t.userId, t.dayKey] })]);

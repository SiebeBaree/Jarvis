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
export const blockStatus = pgEnum("block_status", ["planned", "active", "completed"]);
export const goalStatus = pgEnum("goal_status", ["active", "achieved", "dropped"]);
export const goalTrackStatus = pgEnum("goal_track_status", ["on_track", "at_risk", "done"]);
export const taskStatus = pgEnum("task_status", ["open", "done", "cancelled"]);
export const taskPriority = pgEnum("task_priority", ["low", "medium", "high"]);
export const habitType = pgEnum("habit_type", ["daily", "multi_daily", "weekly_frequency"]);
export const interviewStatus = pgEnum("interview_status", [
  "active",
  "completed",
  "applied",
  "abandoned",
]);
export const conversationKind = pgEnum("conversation_kind", [
  "chat",
  "weekly_review",
  "block_review",
  "seeding",
]);
export const memorySource = pgEnum("memory_source", ["chat", "seeding", "manual"]);
export const messageRole = pgEnum("message_role", ["user", "assistant", "tool"]);
export const actionStatus = pgEnum("action_status", ["proposed", "executed", "rejected", "expired"]);
export const briefingKind = pgEnum("briefing_kind", ["morning", "wrapup"]);

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
export type AiOverrides = Partial<{
  baseUrl: string;
  authMode: "api_key" | "codex_oauth";
  deepModel: string;
  fastModel: string;
  deepEffort: string;
  fastEffort: string;
  codexAccessToken: string;
  codexRefreshToken: string;
}>;

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
  aiOverrides: jsonb("ai_overrides").$type<AiOverrides>().notNull().default(sql`'{}'::jsonb`),
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

// ---------- 12 Week Year ----------
export const vision = pgTable("vision", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  content: text("content").notNull().default(""),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const blocks = pgTable("blocks", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  number: integer("number").notNull(), // lifetime counter: 1, 2, 3...
  title: text("title").notNull(),
  startDate: date("start_date").notNull(), // a Monday (dayKey)
  endDate: date("end_date").notNull(), // startDate + 13*7 - 1 (12 weeks + review week)
  status: blockStatus("status").notNull().default("planned"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  uniqueIndex("blocks_user_number_uq").on(t.userId, t.number),
  index("blocks_user_dates_idx").on(t.userId, t.startDate, t.endDate),
]);
// App-enforced invariants: blocks never overlap; at most one is 'active'.

export const goals = pgTable("goals", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  // Nullable: Stage 1 allows manual goals before any block exists.
  blockId: uuid("block_id").references(() => blocks.id, { onDelete: "cascade" }),
  areaId: uuid("area_id").references(() => areas.id, { onDelete: "set null" }),
  title: text("title").notNull(),
  description: text("description"),
  status: goalStatus("status").notNull().default("active"),
  trackStatus: goalTrackStatus("track_status"), // set during weekly reviews (Stage 4)
  manualProgress: smallint("manual_progress"), // 0-100 override; null = computed from tactics
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("goals_user_block_idx").on(t.userId, t.blockId)]);

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
  goalId: uuid("goal_id").references(() => goals.id, { onDelete: "set null" }),
  categoryId: uuid("category_id").references(() => taskCategories.id, { onDelete: "set null" }),
  dueTime: time("due_time"),
  rule: jsonb("rule").$type<RecurrenceRule>().notNull(),
  startDate: date("start_date").notNull(),
  endDate: date("end_date"), // null = forever
  pausedAt: timestamp("paused_at", { withTimezone: true }),
  lastGeneratedThrough: date("last_generated_through"), // materialization high-water mark
  // Week 13 pauses tasks; date-critical recurrences (e.g. monthly investor
  // update) can opt in to still appearing (they never score during week 13).
  showInReviewWeek: boolean("show_in_review_week").notNull().default(false),
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
  goalId: uuid("goal_id").references(() => goals.id, { onDelete: "set null" }),
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
  goalId: uuid("goal_id").references(() => goals.id, { onDelete: "set null" }),
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

// ---------- tactics (12 Week Year execution layer — feed goal progress, not the daily score) ----------
export const tactics = pgTable("tactics", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  goalId: uuid("goal_id")
    .notNull()
    .references(() => goals.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  fromWeek: smallint("from_week").notNull().default(1), // 1-12
  toWeek: smallint("to_week").notNull().default(12),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("tactics_goal_idx").on(t.goalId)]);

export const tacticCompletions = pgTable("tactic_completions", {
  id: uuid("id").primaryKey().defaultRandom(),
  tacticId: uuid("tactic_id")
    .notNull()
    .references(() => tactics.id, { onDelete: "cascade" }),
  weekNumber: smallint("week_number").notNull(), // 1-12 within the block
  completedAt: timestamp("completed_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [uniqueIndex("tactic_completions_week_uq").on(t.tacticId, t.weekNumber)]);

// ---------- AI: profile & interview ----------
export type UserProfileData = {
  values: string[];
  constraints: string[];
  schedule: string;
  motivations: string[];
  context: string; // free-form summary of what Jarvis knows
};

export const userProfile = pgTable("user_profile", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  data: jsonb("data").$type<UserProfileData>().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const interviewSessions = pgTable("interview_sessions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  kind: text("kind").notNull().default("onboarding"), // onboarding | reonboarding | vision
  status: interviewStatus("status").notNull().default("active"),
  // Full history: [{ round, phase, questions: [...], answers: [...] }]
  transcript: jsonb("transcript").$type<unknown[]>().notNull().default(sql`'[]'::jsonb`),
  providerResponseId: text("provider_response_id"), // OpenAI Responses chaining
  result: jsonb("result"), // completion payload (profile + visionDraft + areas + plan)
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  completedAt: timestamp("completed_at", { withTimezone: true }),
});

// ---------- AI: conversations, messages, action cards, briefings ----------

export type MessagePart =
  | { type: "text"; text: string }
  | { type: "tool_call"; callId: string; name: string; args: unknown }
  | { type: "tool_result"; callId: string; result: unknown };

export const conversations = pgTable("conversations", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  kind: conversationKind("kind").notNull().default("chat"),
  title: text("title"), // AI-generated after the first exchange
  blockId: uuid("block_id").references(() => blocks.id, { onDelete: "set null" }),
  weekNumber: integer("week_number"), // weekly_review: 1-13
  outcome: jsonb("outcome"), // structured review summary once closed
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("conversations_user_idx").on(t.userId, t.updatedAt)]);

export const messages = pgTable("messages", {
  id: uuid("id").primaryKey().defaultRandom(),
  conversationId: uuid("conversation_id")
    .notNull()
    .references(() => conversations.id, { onDelete: "cascade" }),
  role: messageRole("role").notNull(),
  parts: jsonb("parts").$type<MessagePart[]>().notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("messages_conv_idx").on(t.conversationId, t.createdAt)]);

export const proposedActions = pgTable("proposed_actions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  conversationId: uuid("conversation_id")
    .notNull()
    .references(() => conversations.id, { onDelete: "cascade" }),
  messageId: uuid("message_id")
    .notNull()
    .references(() => messages.id, { onDelete: "cascade" }),
  toolName: text("tool_name").notNull(),
  args: jsonb("args").notNull(), // zod-validated tool args
  summary: text("summary").notNull(), // template-generated card text (not model-written)
  status: actionStatus("status").notNull().default("proposed"),
  result: jsonb("result"), // execution result or rejection note
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  resolvedAt: timestamp("resolved_at", { withTimezone: true }),
}, (t) => [index("actions_conv_status_idx").on(t.conversationId, t.status)]);

export const briefings = pgTable("briefings", {
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  dayKey: date("day_key").notNull(),
  kind: briefingKind("kind").notNull().default("morning"),
  content: text("content").notNull(), // markdown
  // Wrap-ups regenerate when the day materially changed since generation.
  fingerprint: text("fingerprint"),
  model: text("model").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [primaryKey({ columns: [t.userId, t.dayKey, t.kind] })]);

// ---------- AI memory (one durable fact per row) ----------
// Auto-extracted after chat turns; fully user-editable in the Memory screen.

export const memories = pgTable("memories", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  category: text("category").notNull(), // identity|work|health|appearance|preferences|relationships|context
  content: text("content").notNull(),
  source: memorySource("source").notNull().default("chat"),
  conversationId: uuid("conversation_id").references(() => conversations.id, { onDelete: "set null" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("memories_user_idx").on(t.userId, t.category)]);

// ---------- improvement areas & weekly photo check-ins ----------
// Self-improvement areas (posture, clothing, teeth...). One photo check-in per
// area per week (weekKey = that week's Monday); AI commentary is generated
// asynchronously after upload. Never feeds the daily score.

export const improvementAreas = pgTable("improvement_areas", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  emoji: varchar("emoji", { length: 16 }),
  // What "better" looks like, in the user's words — feeds the commentary prompt.
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
  aiCommentary: text("ai_commentary"), // null until generated (async via after())
  aiModel: text("ai_model"),
  aiGeneratedAt: timestamp("ai_generated_at", { withTimezone: true }),
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
  isReviewWeek: boolean("is_review_week").notNull().default(false),
  breakdown: jsonb("breakdown").$type<ScoreBreakdown>().notNull(),
  isFinal: boolean("is_final").notNull().default(false),
  computedAt: timestamp("computed_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [primaryKey({ columns: [t.userId, t.dayKey] })]);

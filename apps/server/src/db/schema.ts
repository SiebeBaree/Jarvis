import { sql } from "drizzle-orm";
import { check, pgTable, smallint, text, timestamp } from "drizzle-orm/pg-core";

/**
 * Singleton settings row. Always `id = 1`; the CHECK constraint enforces the
 * single-row invariant at the database level.
 */
export const settings = pgTable(
  "settings",
  {
    id: smallint("id").primaryKey().default(1),
    timezone: text("timezone").notNull().default("Europe/Brussels"),
    dayEndsAt: text("day_ends_at").notNull().default("03:00"),
    expoPushToken: text("expo_push_token"),
    morningBriefingAt: text("morning_briefing_at"),
    eveningReviewAt: text("evening_review_at"),
    coachModel: text("coach_model")
      .notNull()
      .default("anthropic/claude-sonnet-5"),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [check("settings_singleton", sql`${table.id} = 1`)],
);

export type SettingsRow = typeof settings.$inferSelect;
export type NewSettingsRow = typeof settings.$inferInsert;

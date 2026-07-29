ALTER TABLE "blocks" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "briefings" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "conversations" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "goals" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "interview_sessions" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "memories" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "messages" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "proposed_actions" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "tactic_completions" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "tactics" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "user_profile" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "vision" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
DROP TABLE "blocks" CASCADE;--> statement-breakpoint
DROP TABLE "briefings" CASCADE;--> statement-breakpoint
DROP TABLE "conversations" CASCADE;--> statement-breakpoint
DROP TABLE "goals" CASCADE;--> statement-breakpoint
DROP TABLE "interview_sessions" CASCADE;--> statement-breakpoint
DROP TABLE "memories" CASCADE;--> statement-breakpoint
DROP TABLE "messages" CASCADE;--> statement-breakpoint
DROP TABLE "proposed_actions" CASCADE;--> statement-breakpoint
DROP TABLE "tactic_completions" CASCADE;--> statement-breakpoint
DROP TABLE "tactics" CASCADE;--> statement-breakpoint
DROP TABLE "user_profile" CASCADE;--> statement-breakpoint
DROP TABLE "vision" CASCADE;--> statement-breakpoint
ALTER TABLE "habits" DROP CONSTRAINT "habits_goal_id_goals_id_fk";
--> statement-breakpoint
ALTER TABLE "recurrence_templates" DROP CONSTRAINT "recurrence_templates_goal_id_goals_id_fk";
--> statement-breakpoint
ALTER TABLE "tasks" DROP CONSTRAINT "tasks_goal_id_goals_id_fk";
--> statement-breakpoint
ALTER TABLE "area_checkins" DROP COLUMN "ai_commentary";--> statement-breakpoint
ALTER TABLE "area_checkins" DROP COLUMN "ai_model";--> statement-breakpoint
ALTER TABLE "area_checkins" DROP COLUMN "ai_generated_at";--> statement-breakpoint
ALTER TABLE "daily_scores" DROP COLUMN "is_review_week";--> statement-breakpoint
ALTER TABLE "habits" DROP COLUMN "goal_id";--> statement-breakpoint
ALTER TABLE "recurrence_templates" DROP COLUMN "goal_id";--> statement-breakpoint
ALTER TABLE "recurrence_templates" DROP COLUMN "show_in_review_week";--> statement-breakpoint
ALTER TABLE "settings" DROP COLUMN "ai_overrides";--> statement-breakpoint
ALTER TABLE "tasks" DROP COLUMN "goal_id";--> statement-breakpoint
DROP TYPE "public"."action_status";--> statement-breakpoint
DROP TYPE "public"."block_status";--> statement-breakpoint
DROP TYPE "public"."briefing_kind";--> statement-breakpoint
DROP TYPE "public"."conversation_kind";--> statement-breakpoint
DROP TYPE "public"."goal_status";--> statement-breakpoint
DROP TYPE "public"."goal_track_status";--> statement-breakpoint
DROP TYPE "public"."interview_status";--> statement-breakpoint
DROP TYPE "public"."memory_source";--> statement-breakpoint
DROP TYPE "public"."message_role";
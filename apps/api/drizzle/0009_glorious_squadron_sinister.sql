ALTER TABLE "exercises" ADD COLUMN "load_style" text DEFAULT 'plates' NOT NULL;--> statement-breakpoint
-- Backfill: guess the ladder from the movement's name, same rules the app uses
-- when a new exercise is created. Anything unmatched stays on plates.
UPDATE "exercises" SET "load_style" = 'cable' WHERE "load_style" = 'plates' AND (
  "name" ILIKE '%cable%' OR "name" ILIKE '%pulldown%' OR "name" ILIKE '%pushdown%'
  OR "name" ILIKE '%pulley%' OR "name" ILIKE '%crossover%' OR "name" ILIKE '%rope%'
);--> statement-breakpoint
UPDATE "exercises" SET "load_style" = 'dumbbell' WHERE "load_style" = 'plates' AND (
  "name" ILIKE '%dumbbell%' OR "name" ILIKE '%dumbell%' OR "name" ILIKE '%db %'
);--> statement-breakpoint
UPDATE "exercises" SET "load_style" = 'machine' WHERE "load_style" = 'plates' AND (
  "name" ILIKE '%machine%' OR "name" ILIKE '%leg press%' OR "name" ILIKE '%leg curl%'
  OR "name" ILIKE '%leg extension%' OR "name" ILIKE '%calf%' OR "name" ILIKE '%calve%'
  OR "name" ILIKE '%seated row%' OR "name" ILIKE '%back row%' OR "name" ILIKE '%pec deck%'
  OR "name" ILIKE '%hack squat%' OR "name" ILIKE '%smith%'
);

// Zod schemas for Stage 1 request bodies and queries.
import { z } from "zod";
import { isValidDayKey } from "./daykey";

export const dayKeySchema = z
  .string()
  .refine(isValidDayKey, { message: "must be a valid YYYY-MM-DD date" });

export const timeSchema = z
  .string()
  .regex(/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/, { message: "must be HH:MM" });

export const prioritySchema = z.enum(["low", "medium", "high"]);

// ---------- auth ----------
export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
  deviceName: z.string().max(120).nullish(),
});

export const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8, { message: "password must be at least 8 characters" }),
});

// ---------- settings ----------
export function isValidTimezone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

export const settingsPatchSchema = z
  .object({
    timezone: z
      .string()
      .min(1)
      .refine(isValidTimezone, { message: "must be a valid IANA timezone" })
      .optional(),
    dayBoundaryHour: z.number().int().min(0).max(6).optional(),
    weekStartsOn: z.literal(1).optional(), // Monday only for now
    scoreWeights: z
      .object({
        tasks: z.number().int().min(0).max(100),
        habits: z.number().int().min(0).max(100),
        feel: z.number().int().min(0).max(100),
      })
      .refine((w) => w.tasks + w.habits + w.feel === 100, {
        message: "score weights must sum to 100",
      })
      .optional(),
    moodScaleMax: z.number().int().min(2).max(10).optional(),
  })
  .strict();

// ---------- areas ----------
export const areaCreateSchema = z.object({
  name: z.string().min(1).max(60),
  emoji: z.string().max(16).nullish(),
  colorHex: z
    .string()
    .regex(/^#[0-9a-fA-F]{6,8}$/)
    .nullish(),
  sortOrder: z.number().int().optional(),
});
export const areaPatchSchema = areaCreateSchema.partial().extend({
  archived: z.boolean().optional(),
});

// ---------- goals ----------
const goalValueSchema = z.number().min(-1e11).max(1e11);

const goalBaseSchema = z.object({
  id: z.string().uuid().optional(), // client-chosen so a replayed create is idempotent
  title: z.string().min(1).max(200),
  description: z.string().max(4000).nullish(),
  horizon: z.enum(["short", "long"]).optional(),
  areaId: z.string().uuid().nullish(),
  startDate: dayKeySchema.optional(), // defaults to today
  targetDate: dayKeySchema,
  // Send all three (or none). A partial numeric setup has no meaningful
  // percentage, so it is rejected rather than silently rendered as untracked.
  unit: z.string().min(1).max(20).nullish(),
  startValue: goalValueSchema.nullish(),
  targetValue: goalValueSchema.nullish(),
  currentValue: goalValueSchema.nullish(),
  sortOrder: z.number().int().optional(),
});

/** startValue/targetValue travel together, and a flat target has no progress. */
function refineNumericTracking(
  goal: {
    startValue?: number | null;
    targetValue?: number | null;
  },
  ctx: z.RefinementCtx,
): void {
  const hasStart = goal.startValue !== null && goal.startValue !== undefined;
  const hasTarget = goal.targetValue !== null && goal.targetValue !== undefined;
  if (hasStart !== hasTarget) {
    ctx.addIssue({
      code: "custom",
      message: "startValue and targetValue must be set together",
    });
    return;
  }
  if (hasStart && goal.startValue === goal.targetValue) {
    ctx.addIssue({ code: "custom", message: "targetValue must differ from startValue" });
  }
}

export const goalCreateSchema = goalBaseSchema
  .refine((g) => !g.startDate || g.startDate <= g.targetDate, {
    message: "targetDate must be on or after startDate",
  })
  .superRefine(refineNumericTracking);

export const goalPatchSchema = goalBaseSchema
  .omit({ id: true })
  .partial()
  .extend({ status: z.enum(["active", "achieved", "dropped"]).optional() })
  .strict()
  .refine((g) => !g.startDate || !g.targetDate || g.startDate <= g.targetDate, {
    message: "targetDate must be on or after startDate",
  })
  .superRefine(refineNumericTracking);

export const goalListQuerySchema = z.object({
  includeClosed: z.enum(["true", "false"]).optional(),
});

/** The one-tap "log where I am now" write from the goal card. */
export const goalValuePutSchema = z.object({ currentValue: goalValueSchema });

export const milestoneCreateSchema = z.object({
  id: z.string().uuid().optional(), // client-chosen so a replayed create is idempotent
  title: z.string().min(1).max(200),
  sortOrder: z.number().int().optional(),
});
export const milestonePatchSchema = z
  .object({
    title: z.string().min(1).max(200).optional(),
    done: z.boolean().optional(),
    sortOrder: z.number().int().optional(),
  })
  .strict();

// ---------- improvement areas & check-ins ----------
export const improvementAreaCreateSchema = z.object({
  name: z.string().min(1).max(60),
  emoji: z.string().max(16).nullish(),
  betterLooksLike: z.string().max(2000).nullish(),
  sortOrder: z.number().int().optional(),
});
export const improvementAreaPatchSchema = z
  .object({
    name: z.string().min(1).max(60).optional(),
    emoji: z.string().max(16).nullable().optional(),
    betterLooksLike: z.string().max(2000).nullable().optional(),
    sortOrder: z.number().int().optional(),
    archived: z.boolean().optional(),
  })
  .strict();
export const checkinUploadQuerySchema = z.object({ dayKey: dayKeySchema });

// ---------- account ----------
export const accountResetSchema = z.object({ confirm: z.literal("RESET") });

// ---------- task categories ----------
export const taskCategoryCreateSchema = z.object({
  name: z.string().min(1).max(60),
  emoji: z.string().max(16).nullish(),
  colorHex: z
    .string()
    .regex(/^#[0-9a-fA-F]{6,8}$/)
    .nullish(),
  sortOrder: z.number().int().optional(),
});
export const taskCategoryPatchSchema = taskCategoryCreateSchema.partial().extend({
  archived: z.boolean().optional(),
});

// ---------- tasks ----------
export const taskCreateSchema = z.object({
  id: z.string().uuid().optional(), // client-chosen so a retried create is idempotent
  title: z.string().min(1).max(300),
  notes: z.string().max(5000).nullish(),
  dueDate: dayKeySchema.nullish(),
  dueTime: timeSchema.nullish(),
  priority: prioritySchema.optional(),
  categoryId: z.string().uuid().nullish(),
  parentTaskId: z.string().uuid().nullish(),
  sortOrder: z.number().int().optional(),
});

export const taskPatchSchema = z
  .object({
    title: z.string().min(1).max(300).optional(),
    notes: z.string().max(5000).nullable().optional(),
    dueDate: dayKeySchema.nullable().optional(),
    dueTime: timeSchema.nullable().optional(),
    priority: prioritySchema.optional(),
    categoryId: z.string().uuid().nullable().optional(),
    sortOrder: z.number().int().optional(),
    status: z.enum(["open", "cancelled"]).optional(), // done goes through /complete
  })
  .strict();

export const taskListQuerySchema = z.object({
  view: z.enum(["today", "upcoming", "all", "done", "inbox"]).optional(),
  dueFrom: dayKeySchema.optional(),
  dueTo: dayKeySchema.optional(),
  categoryId: z.string().uuid().optional(),
  status: z.enum(["open", "done", "cancelled"]).optional(),
});

// ---------- recurrence templates ----------
export const recurrenceRuleSchema = z.discriminatedUnion("freq", [
  z.object({ freq: z.literal("daily"), interval: z.number().int().min(1).max(365) }),
  z.object({
    freq: z.literal("weekly"),
    interval: z.number().int().min(1).max(52),
    byWeekday: z.array(z.number().int().min(1).max(7)).min(1).max(7),
  }),
  z.object({
    freq: z.literal("monthly"),
    interval: z.number().int().min(1).max(12),
    byMonthDay: z.number().int().min(1).max(31),
  }),
]);

export const templateCreateSchema = z.object({
  title: z.string().min(1).max(300),
  notes: z.string().max(5000).nullish(),
  priority: prioritySchema.optional(),
  categoryId: z.string().uuid().nullish(),
  dueTime: timeSchema.nullish(),
  rule: recurrenceRuleSchema,
  startDate: dayKeySchema,
  endDate: dayKeySchema.nullish(),
});
export const templatePatchSchema = templateCreateSchema.partial().extend({
  paused: z.boolean().optional(),
});

// ---------- habits ----------
export const habitCreateSchema = z
  .object({
    // Client-generated, so a queued create that gets replayed upserts instead
    // of adding a second copy of the habit.
    id: z.string().uuid().optional(),
    name: z.string().min(1).max(120),
    icon: z.string().max(80).nullish(),
    colorHex: z
      .string()
      .regex(/^#[0-9a-fA-F]{6,8}$/)
      .nullish(),
    type: z.enum(["daily", "multi_daily", "weekly_frequency"]),
    targetReps: z.number().int().min(1).max(20).optional(),
    plannedDays: z.array(z.number().int().min(1).max(7)).max(7).optional(),
    areaId: z.string().uuid().nullish(),
    startDate: dayKeySchema.optional(), // defaults to today
    sortOrder: z.number().int().optional(),
  })
  .superRefine((h, ctx) => {
    const target = h.targetReps ?? 1;
    if (h.type === "daily" && target !== 1)
      ctx.addIssue({ code: "custom", message: "daily habits have exactly 1 rep per day" });
    if (h.type === "multi_daily" && target < 2)
      ctx.addIssue({ code: "custom", message: "multi-daily habits need at least 2 reps per day" });
    if (h.type === "weekly_frequency" && (target < 1 || target > 7))
      ctx.addIssue({ code: "custom", message: "weekly habits need 1-7 reps per week" });
  });

export const habitPatchSchema = z
  .object({
    name: z.string().min(1).max(120).optional(),
    icon: z.string().max(80).nullable().optional(),
    colorHex: z
      .string()
      .regex(/^#[0-9a-fA-F]{6,8}$/)
      .nullable()
      .optional(),
    targetReps: z.number().int().min(1).max(20).optional(),
    plannedDays: z.array(z.number().int().min(1).max(7)).max(7).optional(),
    areaId: z.string().uuid().nullable().optional(),
    paused: z.boolean().optional(),
    sortOrder: z.number().int().optional(),
  })
  .strict();

export const habitLogSchema = z.object({
  dayKey: dayKeySchema.optional(),
  completionId: z.string().uuid().optional(), // client-chosen so a replayed log never double-counts
});

export const calendarQuerySchema = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/, { message: "must be YYYY-MM" }),
});

// ---------- mood ----------
export const moodPutSchema = z.object({
  value: z.number().int().min(0).max(100),
  note: z.string().max(1000).nullish(),
});

// ---------- scores ----------
export const scoresQuerySchema = z.object({
  from: dayKeySchema,
  to: dayKeySchema,
});
// ---------- body metrics ----------
export const metricTypeCreateSchema = z.object({
  name: z.string().min(1).max(60),
  unit: z.string().min(1).max(20),
  decimals: z.number().int().min(0).max(3).default(1),
  goalValue: z.number().nullish(),
  goalDirection: z.enum(["up", "down"]).nullish(),
});
export const metricTypePatchSchema = metricTypeCreateSchema
  .partial()
  .extend({ archived: z.boolean().optional() })
  .strict();
export const metricTypesQuerySchema = z.object({
  includeArchived: z.enum(["true", "false"]).optional(),
});
export const metricEntriesQuerySchema = z.object({
  typeId: z.string().uuid().optional(), // absent = entries across all types
  from: dayKeySchema.optional(),
  to: dayKeySchema.optional(),
});
export const metricEntryPutSchema = z.object({
  value: z.number(),
});

// ---------- progress photos ----------
export const photosQuerySchema = z.object({
  from: dayKeySchema.optional(),
  to: dayKeySchema.optional(),
});
export const photoUploadQuerySchema = z.object({
  angle: z.string().min(1).max(30),
  dayKey: dayKeySchema,
});

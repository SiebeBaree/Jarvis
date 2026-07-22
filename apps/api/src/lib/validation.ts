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

// ---------- vision ----------
export const visionPutSchema = z.object({
  content: z.string().max(20_000),
});

// ---------- blocks ----------
export const blockCreateSchema = z.object({
  title: z.string().min(1).max(200),
  startDate: dayKeySchema,
});
export const blockPatchSchema = z
  .object({
    title: z.string().min(1).max(200).optional(), // dates are immutable once created
  })
  .strict();

// ---------- goals ----------
export const goalCreateSchema = z.object({
  title: z.string().min(1).max(200),
  description: z.string().max(2000).nullish(),
  areaId: z.string().uuid().nullish(),
  blockId: z.string().uuid().nullish(),
  trackStatus: z.enum(["on_track", "at_risk", "done"]).nullish(),
  manualProgress: z.number().int().min(0).max(100).nullish(), // null clears back to computed
  sortOrder: z.number().int().optional(),
});
export const goalPatchSchema = goalCreateSchema.partial().extend({
  status: z.enum(["active", "achieved", "dropped"]).optional(),
});
export const goalListQuerySchema = z.object({
  includeDropped: z.enum(["true", "false"]).optional(),
  blockId: z.string().uuid().optional(),
});

// ---------- tactics ----------
const tacticWeekSchema = z.number().int().min(1).max(12);
export const tacticCreateSchema = z
  .object({
    goalId: z.string().uuid(),
    title: z.string().min(1).max(300),
    fromWeek: tacticWeekSchema.default(1),
    toWeek: tacticWeekSchema.default(12),
    sortOrder: z.number().int().optional(),
  })
  .refine((t) => t.fromWeek <= t.toWeek, { message: "fromWeek must be <= toWeek" });
export const tacticPatchSchema = z
  .object({
    title: z.string().min(1).max(300).optional(),
    fromWeek: tacticWeekSchema.optional(),
    toWeek: tacticWeekSchema.optional(),
    sortOrder: z.number().int().optional(),
  })
  .strict();
export const tacticListQuerySchema = z
  .object({
    goalId: z.string().uuid().optional(),
    blockId: z.string().uuid().optional(),
  })
  .refine((q) => Boolean(q.goalId) !== Boolean(q.blockId), {
    message: "provide exactly one of goalId or blockId",
  });
export const tacticWeekPutSchema = z.object({ done: z.boolean() });

// ---------- AI memory ----------
export const memoryCategories = [
  "identity",
  "work",
  "health",
  "appearance",
  "preferences",
  "relationships",
  "context",
] as const;
export const memoryCreateSchema = z.object({
  category: z.enum(memoryCategories),
  content: z.string().min(1).max(500),
});
export const memoryPatchSchema = z
  .object({
    category: z.enum(memoryCategories).optional(),
    content: z.string().min(1).max(500).optional(),
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
  title: z.string().min(1).max(300),
  notes: z.string().max(5000).nullish(),
  dueDate: dayKeySchema.nullish(),
  dueTime: timeSchema.nullish(),
  priority: prioritySchema.optional(),
  goalId: z.string().uuid().nullish(),
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
    goalId: z.string().uuid().nullable().optional(),
    categoryId: z.string().uuid().nullable().optional(),
    sortOrder: z.number().int().optional(),
    status: z.enum(["open", "cancelled"]).optional(), // done goes through /complete
  })
  .strict();

export const taskListQuerySchema = z.object({
  view: z.enum(["today", "upcoming", "all", "done", "inbox"]).optional(),
  dueFrom: dayKeySchema.optional(),
  dueTo: dayKeySchema.optional(),
  goalId: z.string().uuid().optional(),
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
  goalId: z.string().uuid().nullish(),
  categoryId: z.string().uuid().nullish(),
  dueTime: timeSchema.nullish(),
  rule: recurrenceRuleSchema,
  startDate: dayKeySchema,
  endDate: dayKeySchema.nullish(),
  showInReviewWeek: z.boolean().optional(),
});
export const templatePatchSchema = templateCreateSchema.partial().extend({
  paused: z.boolean().optional(),
});

// ---------- habits ----------
export const habitCreateSchema = z
  .object({
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
    goalId: z.string().uuid().nullish(),
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
    goalId: z.string().uuid().nullable().optional(),
    paused: z.boolean().optional(),
    sortOrder: z.number().int().optional(),
  })
  .strict();

export const habitLogSchema = z.object({ dayKey: dayKeySchema.optional() });

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
export const weeklyScoresQuerySchema = z.object({
  blockId: z.string().uuid(),
});

// ---------- reviews ----------
export const weeklyReviewStartSchema = z.object({
  weekNumber: z.number().int().min(1).max(13).optional(),
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

// ---------- AI chat ----------
export const chatRequestSchema = z.object({
  conversationId: z.string().uuid().nullish(),
  message: z.string().min(1).max(8000),
  // Kind for a NEW conversation (ignored when conversationId is set).
  // "seeding" = the plan-free get-to-know-you conversation from the setup wizard.
  kind: z.enum(["chat", "seeding"]).optional(),
});
